import cache_pkg::*;

module axi_worker_mem_model #(
    parameter int ADDR_WIDTH     = 32,
    parameter int DATA_WIDTH     = 32,
    parameter int READ_LATENCY   = 2, // Wait states before driving read data
    parameter int WRITE_LATENCY  = 1 // Wait states before acknowledging writes
)(
    axi4_if.worker axi_bus
);
    // Sparse Associative Memory Storage (Byte-addressable)
    logic [7:0] mem [logic [ADDR_WIDTH-1:0]];

    // Read Channel Handling (AR & R Channels)
    logic [ADDR_WIDTH-1:0] read_addr;
    logic [7:0]            read_len;
    logic [2:0]            read_size;

    initial begin
        axi_bus.arready = 1'b0;
        axi_bus.rvalid  = 1'b0;
        axi_bus.rdata   = '0;
        axi_bus.rresp   = AXI_RESP_OKAY;
        axi_bus.rlast   = 1'b0;

        forever begin
            // Wait for active read address request
            @(posedge axi_bus.clk);
            if (!axi_bus.rst_n) begin
                axi_bus.arready <= 1'b0;
                axi_bus.rvalid  <= 1'b0;
            end else if (axi_bus.arvalid) begin
                // Simulate read access latency
                repeat (READ_LATENCY) @(posedge axi_bus.clk);
                
                axi_bus.arready <= 1'b1;
                read_addr        = axi_bus.araddr;
                read_len         = axi_bus.arlen;
                read_size        = axi_bus.arsize;
                @(posedge axi_bus.clk);
                axi_bus.arready <= 1'b0;

                // Drive read burst data beats
                for (int beat = 0; beat <= read_len; beat++) begin
                    axi_bus.rvalid <= 1'b1;
                    axi_bus.rlast  <= (beat == read_len);
                    axi_bus.rresp  <= AXI_RESP_OKAY;

                    // Fetch data byte-by-byte from dynamic array
                    for (int b = 0; b < (DATA_WIDTH / 8); b++) begin
                        if (mem.exists(read_addr + b)) begin
                            axi_bus.rdata[b*8 +: 8] <= mem[read_addr + b];
                        end else begin
                            // Default uninitialized memory value
                            axi_bus.rdata[b*8 +: 8] <= 8'h00;
                        end
                    end

                    // Wait for boss (L1 Cache) handshake
                    do begin
                        @(posedge axi_bus.clk);
                    end while (!axi_bus.rready);

                    read_addr += (1 << read_size);
                end

                axi_bus.rvalid <= 1'b0;
                axi_bus.rlast  <= 1'b0;
            end
        end
    end

    // Write Channel Handling (AW, W, & B Channels)
    logic [ADDR_WIDTH-1:0] write_addr;
    logic [7:0]            write_len;
    logic [2:0]            write_size;

    initial begin
        axi_bus.awready = 1'b0;
        axi_bus.wready  = 1'b0;
        axi_bus.bvalid  = 1'b0;
        axi_bus.bresp   = AXI_RESP_OKAY;

        forever begin
            @(posedge axi_bus.clk);
            if (!axi_bus.rst_n) begin
                axi_bus.awready <= 1'b0;
                axi_bus.wready  <= 1'b0;
                axi_bus.bvalid  <= 1'b0;
            end else if (axi_bus.awvalid) begin
                // Accept write address
                repeat (WRITE_LATENCY) @(posedge axi_bus.clk);
                axi_bus.awready <= 1'b1;
                write_addr       = axi_bus.awaddr;
                write_len        = axi_bus.awlen;
                write_size       = axi_bus.awsize;
                @(posedge axi_bus.clk);
                axi_bus.awready <= 1'b0;

                // Receive burst beats
                for (int beat = 0; beat <= write_len; beat++) begin
                    axi_bus.wready <= 1'b1;

                    do begin
                        @(posedge axi_bus.clk);
                    end while (!axi_bus.wvalid);

                    // Store incoming bytes into dynamic array based on byte enables
                    for (int b = 0; b < (DATA_WIDTH / 8); b++) begin
                        if (axi_bus.wstrb[b]) begin
                            mem[write_addr + b] = axi_bus.wdata[b*8 +: 8];
                        end
                    end

                    write_addr += (1 << write_size);
                end

                axi_bus.wready <= 1'b0;

                // Send write response (B Channel)
                axi_bus.bvalid <= 1'b1;
                axi_bus.bresp  <= AXI_RESP_OKAY;

                do begin
                    @(posedge axi_bus.clk);
                end while (!axi_bus.bready);

                axi_bus.bvalid <= 1'b0;
            end
        end
    end

endmodule