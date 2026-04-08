`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench 1: Cold Misses then Cache Hits
//
// Purpose: Verify basic cache functionality (no LRU pressure)
//   Phase 1 - Access 20 brand new blocks -> 20 cold misses (cache is empty)
//   Phase 2 - Re-access 10 of those blocks -> 10 hits
//
// Address breakdown:
//   addr[10:8] = tag        (3 bits)
//   addr[7:4]  = set_index  (4 bits)
//   addr[3:0]  = block_off  (4 bits)
//
// All 20 blocks use tag=0 or tag=1, spread across sets 0-15.
// No set is filled beyond 2 ways so no LRU eviction occurs here.
//////////////////////////////////////////////////////////////////////////////////

module tb_cold_miss_and_hit;

    reg         clk, rst, cs, rd;
    reg  [10:0] addr;
    wire [31:0] data_out;
    wire        hit;
    wire        busy;

    integer total_accesses;
    integer total_hits;
    integer total_misses;

    cache_4way dut (
        .clk     (clk),
        .rst     (rst),
        .cs      (cs),
        .rd      (rd),
        .addr    (addr),
        .data_out(data_out),
        .hit     (hit),
        .busy    (busy)
    );

    always #5 clk = ~clk;

    // Task: send one request and wait for completion via busy handshake.
    // hit is sampled while FSM is in S1 (busy=1) before it returns to S0.
    task send_request;
        input [10:0] address;
        reg captured_hit;
        reg [31:0] captured_data;
        begin
            addr = address;
            @(posedge clk);           // FSM registers request S0 -> S1
            wait(busy == 1);          // FSM is now in S1 - sample hit here
            captured_hit = hit;
            wait(busy == 0);          // FSM finishes, back to S0
            captured_data = data_out;
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

        #20;
        rst = 0;

        // Preload RAM: mem[line][word] = (line << 8) + word
        for (i = 0; i < 128; i = i + 1) begin : ram_init
            integer w;
            for (w = 0; w < 16; w = w + 1)
                dut.ram_inst.mem[i][w] = (i << 8) + w;
        end
        $display("RAM preloaded.");

        #20;
        cs = 1;
        rd = 1;

        // ==============================================================
        // PHASE 1: 20 Cold Misses
        // Blocks 0-15  : tag=0, sets 0-15  (addresses 0x003 to 0x0F3)
        // Blocks 16-19 : tag=1, sets 0-3   (addresses 0x103 to 0x133)
        // Cache is empty so every access is a miss.
        // ==============================================================
        $display("");
        $display("=== PHASE 1: 20 Cold Misses (cache is empty) ===");

        send_request(11'h003);   // tag=0 set=0  line=0
        send_request(11'h013);   // tag=0 set=1  line=1
        send_request(11'h023);   // tag=0 set=2  line=2
        send_request(11'h033);   // tag=0 set=3  line=3
        send_request(11'h043);   // tag=0 set=4  line=4
        send_request(11'h053);   // tag=0 set=5  line=5
        send_request(11'h063);   // tag=0 set=6  line=6
        send_request(11'h073);   // tag=0 set=7  line=7
        send_request(11'h083);   // tag=0 set=8  line=8
        send_request(11'h093);   // tag=0 set=9  line=9
        send_request(11'h0A3);   // tag=0 set=10 line=10
        send_request(11'h0B3);   // tag=0 set=11 line=11
        send_request(11'h0C3);   // tag=0 set=12 line=12
        send_request(11'h0D3);   // tag=0 set=13 line=13
        send_request(11'h0E3);   // tag=0 set=14 line=14
        send_request(11'h0F3);   // tag=0 set=15 line=15
        send_request(11'h103);   // tag=1 set=0  line=16
        send_request(11'h113);   // tag=1 set=1  line=17
        send_request(11'h123);   // tag=1 set=2  line=18
        send_request(11'h133);   // tag=1 set=3  line=19

        $display("--- Phase 1 complete: expect 20 misses ---");

        @(posedge clk);   // allow FSM to settle before Phase 2
        @(posedge clk);

        // ==============================================================
        // PHASE 2: 10 Cache Hits
        // Re-access blocks already loaded in Phase 1.
        // All should be hits since no eviction happened yet.
        // ==============================================================
        $display("");
        $display("=== PHASE 2: Re-accessing loaded blocks (expect HITs) ===");

        send_request(11'h003);   // tag=0 set=0  already in cache
        send_request(11'h043);   // tag=0 set=4  already in cache
        send_request(11'h083);   // tag=0 set=8  already in cache
        send_request(11'h0C3);   // tag=0 set=12 already in cache
        send_request(11'h0F3);   // tag=0 set=15 already in cache
        send_request(11'h103);   // tag=1 set=0  already in cache
        send_request(11'h113);   // tag=1 set=1  already in cache
        send_request(11'h123);   // tag=1 set=2  already in cache
        send_request(11'h133);   // tag=1 set=3  already in cache
        send_request(11'h023);   // tag=0 set=2  already in cache

        $display("--- Phase 2 complete: expect 10 hits ---");

        cs = 0;
        rd = 0;
        #20;

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