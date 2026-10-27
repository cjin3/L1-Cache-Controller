`timescale 1ns/1ps
import cache_pkg::*;

module tb_top;
    logic clk;
    logic rst_n;

    always #5 clk = ~clk;

    // Interface instantiations
    cpu_if #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) cpu_bus (
        .clk(clk),
        .rst_n(rst_n)
    );

    axi4_if #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) axi_bus (
        .clk(clk),
        .rst_n(rst_n)
    );

    // Device Under Test (DUT) & Memory VIP Instantiations
    l1_cache #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .CACHE_SIZE_BYTES(4096),
        .LINE_SIZE_BYTES(32),
        .ASSOCIATIVITY(4)
    ) dut (
        .cpu_bus(cpu_bus.worker),
        .axi_bus(axi_bus.boss)
    );

    axi_worker_mem_model #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .READ_LATENCY(2),
        .WRITE_LATENCY(1)
    ) mem_model (
        .axi_bus(axi_bus.worker)
    );

    // Verification sequence task helpers
    task automatic cpu_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk);
        cpu_bus.req   <= 1'b1;
        cpu_bus.write <= 1'b0;
        cpu_bus.addr  <= addr;
        cpu_bus.wstrb <= '0;

        do begin
            @(posedge clk);
        end while (!cpu_bus.ready);

        data        = cpu_bus.rdata;
        cpu_bus.req <= 1'b0;
    endtask

    task automatic cpu_write(input logic [31:0] addr, input logic [31:0] data, input logic [3:0] strb = 4'hF);
        @(posedge clk);
        cpu_bus.req   <= 1'b1;
        cpu_bus.write <= 1'b1;
        cpu_bus.addr  <= addr;
        cpu_bus.wdata <= data;
        cpu_bus.wstrb <= strb;

        do begin
            @(posedge clk);
        end while (!cpu_bus.ready);

        cpu_bus.req   <= 1'b0;
        cpu_bus.write <= 1'b0;
    endtask

    // Main verification test stimulus
    logic [31:0] read_val;

    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;
        cpu_bus.req   = 1'b0;
        cpu_bus.write = 1'b0;
        cpu_bus.addr  = '0;
        cpu_bus.wdata = '0;
        cpu_bus.wstrb = '0;

        // Reset
        #20 rst_n = 1'b1;
        $display("[%0t ns] --- Starting L1 Cache Verification Suite ---", $time);

        // Pre-load main memory with data at address 0x0000_1000
        mem_model.mem[32'h0000_1000] = 8'hDE;
        mem_model.mem[32'h0000_1001] = 8'hAD;
        mem_model.mem[32'h0000_1002] = 8'hBE;
        mem_model.mem[32'h0000_1003] = 8'hEF;

        // Test 1: Read miss (forces AXI line allocation)
        $display("[%0t ns] TEST 1: Issuing Read to 0x0000_1000 (Expecting Read Miss)...", $time);
        cpu_read(32'h0000_1000, read_val);
        assert (read_val == 32'hEFBEADDE) 
            else $error("[%0t ns] TEST 1 FAILED: Expected 0xEFBEADDE, got 0x%h", $time, read_val);
        $display("[%0t ns] TEST 1 PASSED: Read Data = 0x%h", $time, read_val);

        // Test 2: Read hit (data should return immediately from cache)
        $display("[%0t ns] TEST 2: Re-issuing Read to 0x0000_1000 (Expecting Read Hit)...", $time);
        cpu_read(32'h0000_1000, read_val);
        assert (cpu_bus.hit == 1'b1) 
            else $error("[%0t ns] TEST 2 FAILED: Expected Cache Hit!", $time);
        $display("[%0t ns] TEST 2 PASSED: Hit Confirmed, Read Data = 0x%h", $time, read_val);

        // Test 3: Write Hht (update line and set dirty bit)
        $display("[%0t ns] TEST 3: Writing 0x12345678 to 0x0000_1000...", $time);
        cpu_write(32'h0000_1000, 32'h12345678);
        
        // Test 4: Verify read after write
        cpu_read(32'h0000_1000, read_val);
        assert (read_val == 32'h12345678) 
            else $error("[%0t ns] TEST 4 FAILED: Read back wrong data!", $time);
        $display("[%0t ns] TEST 4 PASSED: Read-after-write success = 0x%h", $time, read_val);

        $display("[%0t ns] --- ALL TESTS PASSED SUCCESSFULLY ---", $time);
        $finish;
    end

endmodule