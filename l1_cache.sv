
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
    localparam int OFFSET_BITS = $clog2(LINE_SIZE_BYTES)
    localparam int NUM_SETS = CACHE_SIZE_BYTES / (LINE_SIZE_BYTES * ASSOCIATIVITY)
    localparam int INDEX_BITS = $clog2(NUM_SETS)
    localparam int TAG_BITS = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS

    //Packed cache line definition
    typedef struct packed {
        logic                    valid;
        logic                    dirty;
        logic [TAG_BITS-1:0]     tag;
        logic [LINE_SIZE_BYTES*8-1:0] data;
    } cache_line_t;

    //Cache storage array: [NUM_SETS][ASSOCIATIVITY]
    cache_line_t cache_mem [NUM_SETS-1:0][ASSOCIATIVITY-1:0];

    //LRU tracking array
    logic [ASSOCIATIVITY-2:0] lru_bits [NUM_SETS-1:0];

endmodule