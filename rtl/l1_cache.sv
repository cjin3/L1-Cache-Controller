
module l1_cache #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int CACHE_SIZE_BYTES = 4096,
    parameter int LINE_SIZE_BYTES = 32,
    parameter int ASSOCIATIVITY = 4
)(
    input logic clk,
    input logic rst_n
);

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

endmodule