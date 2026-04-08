`timescale 1ns / 1ps
module tb_lru_eviction;

    reg         clk, rst, cs, rd;
    reg  [10:0] addr;
    wire [31:0] data_out;
    wire        hit;
    wire        busy;

    integer total_accesses;
    integer total_hits;
    integer total_misses;

    cache_4way dut (
        .clk(clk), .rst(rst), .cs(cs), .rd(rd),
        .addr(addr), .data_out(data_out), .hit(hit), .busy(busy)
    );

    always #5 clk = ~clk;

    task send_request;
        input [10:0] address;
        reg captured_hit;
        reg [31:0] captured_data;
        begin
            addr = address;
            cs   = 1;
            rd   = 1;
            @(posedge clk);      // FSM: S0 -> S1
            wait(busy == 1);     // FSM is now busy (in S1)
            captured_hit = hit;  // sample hit while in S1
            wait(busy == 0);     // FSM finishes, returns to S0
            cs = 0;              // deassert IMMEDIATELY before any clock edge
            rd = 0;              // prevents FSM from re-triggering on same addr
            @(posedge clk);      // settle - FSM stays in S0
            captured_data = data_out;
            @(posedge clk);      // idle gap between requests
            total_accesses = total_accesses + 1;
            if (captured_hit) begin
                total_hits = total_hits + 1;
                $display("  HIT  | addr=0x%03X | tag=%0d set=%0d | data=0x%08X",
                          address, address[10:8], address[7:4], captured_data);
            end else begin
                total_misses = total_misses + 1;
                $display("  MISS | addr=0x%03X | tag=%0d set=%0d | data=0x%08X",
                          address, address[10:8], address[7:4], captured_data);
            end
        end
    endtask

    integer i;

    initial begin
        clk            = 0;
        rst            = 1;
        cs             = 0;
        rd             = 0;
        addr           = 0;
        total_accesses = 0;
        total_hits     = 0;
        total_misses   = 0;

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        @(posedge clk);

        for (i = 0; i < 128; i = i + 1) begin : ram_init
            integer w;
            for (w = 0; w < 16; w = w + 1)
                dut.ram_inst.mem[i][w] = (i << 8) + w;
        end
        $display("RAM preloaded.");

        $display("");
        $display("=== PHASE 1: Fill sets 0,1,2,3 (expect 16 misses) ===");
        $display("  -- Set 0 --");
        send_request(11'h003);   // tag=0 set=0
        send_request(11'h103);   // tag=1 set=0
        send_request(11'h203);   // tag=2 set=0
        send_request(11'h303);   // tag=3 set=0
        $display("  -- Set 1 --");
        send_request(11'h013);   // tag=0 set=1
        send_request(11'h113);   // tag=1 set=1
        send_request(11'h213);   // tag=2 set=1
        send_request(11'h313);   // tag=3 set=1
        $display("  -- Set 2 --");
        send_request(11'h023);   // tag=0 set=2
        send_request(11'h123);   // tag=1 set=2
        send_request(11'h223);   // tag=2 set=2
        send_request(11'h323);   // tag=3 set=2
        $display("  -- Set 3 --");
        send_request(11'h033);   // tag=0 set=3
        send_request(11'h133);   // tag=1 set=3
        send_request(11'h233);   // tag=2 set=3
        send_request(11'h333);   // tag=3 set=3
        $display("--- Phase 1 complete ---");

        $display("");
        $display("=== PHASE 2: Load tag=4, evict tag=0 (expect 4 misses) ===");
        send_request(11'h403);   // tag=4 set=0 -> evicts tag=0
        send_request(11'h413);   // tag=4 set=1 -> evicts tag=0
        send_request(11'h423);   // tag=4 set=2 -> evicts tag=0
        send_request(11'h433);   // tag=4 set=3 -> evicts tag=0
        $display("--- Phase 2 complete ---");

        $display("");
        $display("=== PHASE 3: Verify evictions ===");
        $display("  -- Expect HIT: tag=1,2,3,4 still in cache --");
        send_request(11'h103);   // tag=1 set=0 -> HIT
        send_request(11'h113);   // tag=1 set=1 -> HIT
        send_request(11'h203);   // tag=2 set=0 -> HIT
        send_request(11'h213);   // tag=2 set=1 -> HIT
        send_request(11'h303);   // tag=3 set=0 -> HIT
        send_request(11'h313);   // tag=3 set=1 -> HIT
        send_request(11'h403);   // tag=4 set=0 -> HIT
        send_request(11'h413);   // tag=4 set=1 -> HIT
        $display("  -- Expect MISS: tag=0 was evicted --");
        send_request(11'h003);   // tag=0 set=0 -> MISS
        send_request(11'h013);   // tag=0 set=1 -> MISS
        send_request(11'h023);   // tag=0 set=2 -> MISS
        send_request(11'h033);   // tag=0 set=3 -> MISS
        $display("--- Phase 3 complete ---");

        cs = 0; rd = 0;
        #50;

        $display("");
        $display("==================== STATISTICS ====================");
        $display("  Total accesses : %0d", total_accesses);
        $display("  Total hits      : %0d", total_hits);
        $display("  Total misses    : %0d", total_misses);
        $display("  Hit rate        : %0d%%", (total_hits   * 100) / total_accesses);
        $display("  Miss rate       : %0d%%", (total_misses * 100) / total_accesses);
        $display("  AMAT            : 2 + (%0d%% x 2) cycles",
                  (total_misses * 100) / total_accesses);
        $display("=====================================================");
        $display("=== Simulation complete ===");
        $stop;
    end

endmodule