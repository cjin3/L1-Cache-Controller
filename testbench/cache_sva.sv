
module cache_sva #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n,
    input logic req,
    input logic ready,
    input logic hit,
    input logic arvalid,
    input logic arready,
    input logic awvalid,
    input logic awready,
    input logic wvalid,
    input logic wready,
    input logic wlast
);

    // Default clocking block
    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    // Protocol: AXI ARVALID must remain asserted until ARREADY is received
    property p_arvalid_stability;
        arvalid && !arready |=> arvalid;
    endproperty
    assert property (p_arvalid_stability)
        else $error("[SVA ERROR] ARVALID dropped before ARREADY handshake!");

    // Coherence: A cache hit must NEVER trigger an AXI Read/Write transaction
    property p_no_axi_on_hit;
        (req && hit) |-> (!arvalid && !awvalid);
    endproperty
    assert property (p_no_axi_on_hit)
        else $error("[SVA ERROR] AXI transaction initiated during a Cache Hit!");

    // Protocol: WLAST must be asserted concurrently with the final WVALID beat
    property p_wlast_asserted;
        wlast |-> wvalid;
    endproperty
    assert property (p_wlast_asserted)
        else $error("[SVA ERROR] WLAST asserted without WVALID!");

endmodule