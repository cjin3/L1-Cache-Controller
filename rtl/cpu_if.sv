
interface cpu_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    // Request & Data Signals
    logic                  req;        // 1 = Request Active
    logic                  write;      // 1 = Write operation, 0 = Read operation
    logic [ADDR_WIDTH-1:0] addr;       // CPU Target Byte Address
    logic [DATA_WIDTH-1:0] wdata;      // CPU Write Data Payload
    logic [(DATA_WIDTH/8)-1:0] wstrb;  // Byte-enable Mask (for sub-word writes)
    
    // Response Signals
    logic [DATA_WIDTH-1:0] rdata;      // Cache Read Data Output
    logic                  ready;      // 1 = Transaction Completed / Ready for new req
    logic                  hit;        // 1 = Cache Hit, 0 = Cache Miss

    // Modport for the CPU Driver (boss)
    modport boss (
        input  clk, rst_n, rdata, ready, hit,
        output req, write, addr, wdata, wstrb
    );

    // Modport for the L1 Cache Controller (worker)
    modport worker (
        input  clk, rst_n, req, write, addr, wdata, wstrb,
        output rdata, ready, hit
    );

endinterface : cpu_if