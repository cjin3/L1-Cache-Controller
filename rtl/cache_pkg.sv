package cache_pkg;

    // FSM Controller States
    typedef enum logic [2:0] {
        STATE_IDLE       = 3'b000, // Wait for CPU request
        STATE_TAG_CHECK  = 3'b001, // Compare tags for Hit/Miss
        STATE_ALLOCATE   = 3'b010, // Read line from memory on Miss
        STATE_WRITE_BACK = 3'b011, // Write dirty line to memory before Allocation
        STATE_RESPOND    = 3'b100  // Return read/write status to CPU
    } cache_state_e;

    // AXI4 Burst Types (Fixed, Incremental, Wrap)
    typedef enum logic [1:0] {
        AXI_BURST_FIXED = 2'b00,
        AXI_BURST_INCR  = 2'b01,
        AXI_BURST_WRAP  = 2'b10
    } axi_burst_e;

    // AXI4 Response Status
    typedef enum logic [1:0] {
        AXI_RESP_OKAY   = 2'b00,
        AXI_RESP_EXOKAY = 2'b01,
        AXI_RESP_SLVERR = 2'b10,
        AXI_RESP_DECERR = 2'b11
    } axi_resp_e;

endpackage : cache_pkg