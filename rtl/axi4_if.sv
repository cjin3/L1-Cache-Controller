

interface axi4_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    // Read Address Channel (AR)
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;    // Burst Length = ARLEN + 1
    logic [2:0]            arsize;   // Bytes per transfer (2^ARSIZE)
    logic [1:0]            arburst;  // Burst type (INCR / WRAP)
    logic                  arvalid;
    logic                  arready;

    // Read Data Channel (R)
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;    // Last beat in burst
    logic                  rvalid;
    logic                  rready;

    // Write Address Channel (AW)
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;    // Burst Length = AWLEN + 1
    logic [2:0]            awsize;   // Bytes per transfer (2^AWSIZE)
    logic [1:0]            awburst;  // Burst type
    logic                  awvalid;
    logic                  awready;

    // Write Data Channel (W)
    logic [DATA_WIDTH-1:0] wdata;
    logic [(DATA_WIDTH/8)-1:0] wstrb;
    logic                  wlast;    // Last beat in burst
    logic                  wvalid;
    logic                  wready;

    // Write Response Channel (B)
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready;

    // Modport for the L1 Cache Controller (AXI Master)
    modport master (
        input  clk, rst_n,
        // AR
        output araddr, arlen, arsize, arburst, arvalid,
        input  arready,
        // R
        input  rdata, rresp, rlast, rvalid,
        output rready,
        // AW
        output awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        // W
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        // B
        input  bresp, bvalid,
        output bready
    );

    // Modport for Main Memory / L2 Cache (AXI Slave)
    modport slave (
        input  clk, rst_n,
        // AR
        input  araddr, arlen, arsize, arburst, arvalid,
        output arready,
        // R
        output rdata, rresp, rlast, rvalid,
        input  rready,
        // AW
        input  awaddr, awlen, awsize, awburst, awvalid,
        output awready,
        // W
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        // B
        output bresp, bvalid,
        input  bready
    );

endinterface : axi4_if