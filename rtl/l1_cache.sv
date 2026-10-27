
module l1_cache #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int CACHE_SIZE_BYTES = 4096,
    parameter int LINE_SIZE_BYTES = 32,
    parameter int ASSOCIATIVITY = 4
)(
    cpu_if.worker   cpu_bus,
    axi4_if.boss    axi_bus 
);

    //Reset logic
    always_ff @(posedge cpu_bus.clk or negedge cpu_bus.rst_n) begin
        if (!cpu_bus.rst_n) begin
            //reset placholder
        end
    end

    //Derived parameters
    localparam int OFFSET_BITS = $clog2(LINE_SIZE_BYTES);
    localparam int NUM_SETS = CACHE_SIZE_BYTES / (LINE_SIZE_BYTES * ASSOCIATIVITY);
    localparam int RAW_INDEX_BITS = $clog2(NUM_SETS);
    localparam int INDEX_BITS = (RAW_INDEX_BITS == 0) ? 1 : RAW_INDEX_BITS;
    localparam int TAG_BITS = ADDR_WIDTH - RAW_INDEX_BITS - OFFSET_BITS;
    localparam int BYTES_PER_WORD = DATA_WIDTH / 8;
    localparam int BYTE_OFFSET_BITS.= $clog2(BYTES_PER_WORD);
    localparam int WORD_OFFSET_BITS = OFFSET_BITS - BYTE_OFFSET_BITS;
    localparam int PLRU_BITS = (ASSOCIATIVITY > 1) ? (ASSOCIATIVITY - 1) : 1;

    //Static parameter checks
    initial begin
        assert ($onehot(LINE_SIZE_BYTES)) else $fatal(1, "LINE_SIZE_BYTES must be a power of 2.");
        assert ($onehot(ASSOCIATIVITY))   else $fatal(1, "ASSOCIATIVITY must be a power of 2.");
        assert ($onehot(NUM_SETS))        else $fatal(1, "Calculated NUM_SETS must be a power of 2.");
    end

    //Address structure
    typedef struct packed {
        logic [TAG_BITS-1:0]         tag;
        logic [RAW_INDEX_BITS-1:0]   index;
        logic [WORD_OFFSET_BITS-1:0] word_offset;
        logic [BYTE_OFFSET_BITS-1:0] byte_offset;
    } cache_addr_t;

    //Tag memory structure
    typedef struct packed {
        logic                valid;
        logic                dirty;
        logic [TAG_BITS-1:0] tag;
    } tag_entry_t;

    //Decoupled memory arrays
    tag_entry_t tag_mem [NUM_SETS-1:0][ASSOCIATIVITY-1:0];
    logic [LINE_SIZE_BYTES*8-1:0] data_mem [NUM_SETS-1:0][ASSOCIATIVITY:0];

    //LRU tracking array
    logic [PLRU_BITS-1:0] lru_bits [NUM_SETS-1:0];

    cache_state_e state, next_state;

    //Registered CPU request signals
    logic [ADDR_WIDTH-1:0]       req_addr;
    logic                        req_write;
    logic [DATA_WIDTH-1:0]       req_wdata;
    logic [(DATA_WIDTH/8)-1:0]   req_wstrb;

    //AXI burst counter and line fill buffer
    logic [$clog2(WORDS_PER_LINE)-1:0] burst_cnt;
    logic [LINE_SIZE_BYTES*8-1:0]      line_buffer;

    //Address Breakdown
    logic [TAG_BITS-1:0]         addr_tag;
    logic [INDEX_BITS-1:0]       addr_index;
    logic [WORD_OFFSET_BITS-1:0] addr_word_offset;

    assign addr_tag         = req_addr[ADDR_WIDTH-1 -: TAG_BITS];
    assign addr_index       = (RAW_INDEX_BITS == 0) ? '0 : req_addr[OFFSET_BITS +: INDEX_BITS];
    assign addr_word_offset = req_addr[BYTE_OFFSET_BITS +: WORD_OFFSET_BITS];

    logic [ASSOCIATIVITY-1:0] way_hit;
    logic                     hit_detected;
    logic [WAY_BITS-1:0]      hit_way_idx;
    logic [WAY_BITS-1:0]      victim_way;

    //
    //Tag Matching and Hit Logic
    //
    always_comb begin
        hit_detected = 1'b0;
        hit_way_idx  = '0;
        for (int w = 0; w < ASSOCIATIVITY; w++) begin
            way_hit[w] = tag_mem[addr_index][w].valid && (tag_mem[addr_index][w].tag == addr_tag);
            if (way_hit[w]) begin
                hit_detected = 1'b1;
                hit_way_idx  = WAY_BITS'(w);
            end
        end
    end

    //Selected victim way for allocation/eviction
    assign victim_way = replacement_ptr[addr_index];

    //
    //Sequential FSM & State Registers
    //
    always_ff @(posedge cpu_bus.clk or negedge cpu_bus.rst_n) begin
        if (!cpu_bus.rst_n) begin
            state <= STATE_IDLE;
            req_addr  <= '0;
            req_write <= 1'b0;
            req_wdata <= '0;
            req_wstrb <= '0;
            burst_cnt <= '0;

            for (int s = 0; s < NUM_SETS; s++) begin
                replacement_ptr[s] <= '0;
                for (int w = 0; w < ASSOCIATIVITY; w++) begin
                    tag_mem[s][w].valid <= 1'b0;
                    tag_mem[s][w].dirty <= 1'b0;
                    tag_mem[s][w].tag   <= '0;
                end
            end
        end else begin
            state <= next_state;

            case (state)
                STATE_IDLE: begin
                    if (cpu_bus.req) begin
                        req_addr  <= cpu_bus.addr;
                        req_write <= cpu_bus.write;
                        req_wdata <= cpu_bus.wdata;
                        req_wstrb <= cpu_bus.wstrb;
                    end
                end

                STATE_TAG_CHECK: begin
                    if (hit_detected) begin
                        //Advance round-robin pointer on hit
                        replacement_ptr[addr_index] <= replacement_ptr[addr_index] + 1'b1;

                        if (req_write) begin
                            // Mark dirty and update byte lane writes
                            tag_mem[addr_index][hit_way_idx].dirty <= 1'b1;
                            for (int b = 0; b < BYTES_PER_WORD; b++) begin
                                if (req_wstrb[b]) begin
                                    data_mem[addr_index][hit_way_idx][(addr_word_offset * DATA_WIDTH) + (b*8) +: 8] <= req_wdata[b*8 +: 8];
                                end
                            end
                        end
                    end
                end

                STATE_WRITE_BACK: begin
                    if (axi_bus.wvalid && axi_bus.wready) begin
                        if (axi_bus.wlast) begin
                            burst_cnt <= '0;
                        end else begin
                            burst_cnt <= burst_cnt + 1'b1;
                        end
                    end
                end

                STATE_ALLOCATE: begin
                    if (axi_bus.rvalid && axi_bus.rready) begin
                        //Latch incoming word into line buffer
                        line_buffer[(burst_cnt * DATA_WIDTH) +: DATA_WIDTH] <= axi_bus.rdata;
                        
                        if (axi_bus.rlast) begin
                            burst_cnt <= '0;
                            //Commit fetched line into cache
                            data_mem[addr_index][victim_way] <= {axi_bus.rdata, line_buffer[(LINE_SIZE_BYTES*8)-DATA_WIDTH-1:0]};
                            tag_mem[addr_index][victim_way].valid <= 1'b1;
                            tag_mem[addr_index][victim_way].dirty <= 1'b0;
                            tag_mem[addr_index][victim_way].tag   <= addr_tag;
                        end else begin
                            burst_cnt <= burst_cnt + 1'b1;
                        end
                    end
                end

                STATE_RESPOND: begin
                    //Clear state transitions for core interface handshake
                end
            endcase
        end
    end


    //
    //Next-State and Output Combinational Logic
    //
    always_comb begin
        next_state = state;

        // Default CPU Bus Outputs
        cpu_bus.ready = 1'b0;
        cpu_bus.hit   = 1'b0;
        cpu_bus.rdata = '0;

        // Default AXI Signals
        axi_bus.arvalid = 1'b0;
        axi_bus.araddr  = '0;
        axi_bus.arlen   = 8'(WORDS_PER_LINE - 1);
        axi_bus.arsize  = 3'($clog2(BYTES_PER_WORD));
        axi_bus.arburst = AXI_BURST_INCR;
        axi_bus.rready  = 1'b0;

        axi_bus.awvalid = 1'b0;
        axi_bus.awaddr  = '0;
        axi_bus.awlen   = 8'(WORDS_PER_LINE - 1);
        axi_bus.awsize  = 3'($clog2(BYTES_PER_WORD));
        axi_bus.awburst = AXI_BURST_INCR;

        axi_bus.wvalid  = 1'b0;
        axi_bus.wdata   = '0;
        axi_bus.wstrb   = '1;
        axi_bus.wlast   = 1'b0;
        axi_bus.bready  = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (cpu_bus.req) begin
                    next_state = STATE_TAG_CHECK;
                end
            end

            STATE_TAG_CHECK: begin
                if (hit_detected) begin
                    cpu_bus.hit   = 1'b1;
                    cpu_bus.ready = 1'b1;
                    if (!req_write) begin
                        cpu_bus.rdata = data_mem[addr_index][hit_way_idx][(addr_word_offset * DATA_WIDTH) +: DATA_WIDTH];
                    end
                    next_state = STATE_IDLE;
                end else begin
                    // Miss handling: check if victim is dirty
                    if (tag_mem[addr_index][victim_way].valid && tag_mem[addr_index][victim_way].dirty) begin
                        next_state = STATE_WRITE_BACK;
                    end else begin
                        next_state = STATE_ALLOCATE;
                    end
                end
            end

            STATE_WRITE_BACK: begin
                // Drive AW channel until handshaked
                axi_bus.awvalid = 1'b1;
                axi_bus.awaddr  = {tag_mem[addr_index][victim_way].tag, addr_index, {OFFSET_BITS{1'b0}}};

                // Drive W channel payload
                axi_bus.wvalid = 1'b1;
                axi_bus.wdata  = data_mem[addr_index][victim_way][(burst_cnt * DATA_WIDTH) +: DATA_WIDTH];
                axi_bus.wlast  = (burst_cnt == WORDS_PER_LINE - 1);

                if (axi_bus.wvalid && axi_bus.wready && axi_bus.wlast) begin
                    axi_bus.bready = 1'b1;
                    next_state     = STATE_ALLOCATE;
                end
            end

            STATE_ALLOCATE: begin
                // Drive AR channel
                axi_bus.arvalid = 1'b1;
                axi_bus.araddr  = {addr_tag, addr_index, {OFFSET_BITS{1'b0}}};
                axi_bus.rready  = 1'b1;

                if (axi_bus.rvalid && axi_bus.rlast) begin
                    next_state = STATE_TAG_CHECK; // Re-evaluate request after line allocation
                end
            end

            STATE_RESPOND: begin
                cpu_bus.ready = 1'b1;
                next_state   = STATE_IDLE;
            end

            default: next_state = STATE_IDLE;
        endcase
    end

endmodule