`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench 3: Sequential Access WITHOUT Stride Prefetcher
//
// Purpose: Baseline performance measurement with prefetch_enable=0
//          20 sequential accesses with stride=0x010 (one set apart)
//          All 20 should be cold misses since nothing is prefetched.
//
// Access pattern: 0x003, 0x013, 0x023, ... , 0x133 (stride=0x010)
//
// Expected results:
//   Total accesses : 20
//   Hits           : 0
//   Misses         : 20
//   Hit rate       : 0%
//   Miss rate      : 100%
//   AMAT           : 2 + (100% x 2) = 4.0 cycles
//////////////////////////////////////////////////////////////////////////////////

module tb_no_prefetcher;

    reg         clk, rst;
    reg         cpu_cs, cpu_rd;
    reg  [10:0] cpu_addr;
    reg         prefetch_enable;
    wire [31:0] data_out;
    wire        hit;
    wire        busy;
    wire        prefetch_req;

    // Statistics
    integer total_accesses;
    integer total_hits;
    integer total_misses;
    real    hit_rate;
    real    miss_rate;
    real    amat;

    // Instantiate top module
    top dut (
        .clk            (clk),
        .rst            (rst),
        .cpu_cs         (cpu_cs),
        .cpu_rd         (cpu_rd),
        .cpu_addr       (cpu_addr),
        .prefetch_enable(prefetch_enable),
        .data_out       (data_out),
        .hit            (hit),
        .busy           (busy),
        .prefetch_req   (prefetch_req)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Task: send one CPU request, handshake with busy signal,
    //       deassert cs/rd immediately when done to prevent re-trigger.
    //       10 idle cycles after each request - same as prefetcher tb
    //       to ensure fair comparison.
    // ------------------------------------------------------------------
    task send_request;
        input [10:0] address;
        reg captured_hit;
        reg [31:0] captured_data;
        integer idx;
        begin
            cpu_addr = address;
            cpu_cs   = 1;
            cpu_rd   = 1;
            @(posedge clk);          // cache: S0 -> S1
            wait(busy == 1);         // confirm FSM is busy
            captured_hit = hit;      // sample hit while in S1
            wait(busy == 0);         // FSM finishes, back to S0
            cpu_cs = 0;              // deassert immediately
            cpu_rd = 0;
            // 10 idle cycles - gives prefetcher time to complete
            // (even though disabled here, keeps timing identical)
            for (idx = 0; idx < 10; idx = idx + 1)
                @(posedge clk);
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
        cpu_cs         = 0;
        cpu_rd         = 0;
        cpu_addr       = 0;
        prefetch_enable = 0;        // PREFETCHER DISABLED
        total_accesses = 0;
        total_hits     = 0;
        total_misses   = 0;

        // Reset for 3 clock edges
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        @(posedge clk);

        // Preload RAM: mem[line][word] = (line << 8) + word
        for (i = 0; i < 128; i = i + 1) begin : ram_init
            integer w;
            for (w = 0; w < 16; w = w + 1)
                dut.cache_inst.ram_inst.mem[i][w] = (i << 8) + w;
        end
        $display("RAM preloaded.");
        $display("Prefetch enable = %0d", prefetch_enable);

        $display("");
        $display("=== WITHOUT PREFETCHER: 20 Sequential Accesses (stride=0x010) ===");

        // 20 sequential accesses stride=0x010
        send_request(11'h003);   // access  1: tag=0 set=0
        send_request(11'h013);   // access  2: tag=0 set=1
        send_request(11'h023);   // access  3: tag=0 set=2
        send_request(11'h033);   // access  4: tag=0 set=3
        send_request(11'h043);   // access  5: tag=0 set=4
        send_request(11'h053);   // access  6: tag=0 set=5
        send_request(11'h063);   // access  7: tag=0 set=6
        send_request(11'h073);   // access  8: tag=0 set=7
        send_request(11'h083);   // access  9: tag=0 set=8
        send_request(11'h093);   // access 10: tag=0 set=9
        send_request(11'h0A3);   // access 11: tag=0 set=10
        send_request(11'h0B3);   // access 12: tag=0 set=11
        send_request(11'h0C3);   // access 13: tag=0 set=12
        send_request(11'h0D3);   // access 14: tag=0 set=13
        send_request(11'h0E3);   // access 15: tag=0 set=14
        send_request(11'h0F3);   // access 16: tag=0 set=15
        send_request(11'h103);   // access 17: tag=1 set=0
        send_request(11'h113);   // access 18: tag=1 set=1
        send_request(11'h123);   // access 19: tag=1 set=2
        send_request(11'h133);   // access 20: tag=1 set=3

        cpu_cs = 0;
        cpu_rd = 0;
        #50;

        // Compute statistics
        hit_rate  = (total_hits  * 100.0) / total_accesses;
        miss_rate = (total_misses * 100.0) / total_accesses;
        amat      = 2.0 + (miss_rate / 100.0) * 2.0;

        $display("");
        $display("============================================================");
        $display("         RESULTS: WITHOUT PREFETCHER                        ");
        $display("============================================================");
        $display("  Total accesses  : %0d",   total_accesses);
        $display("  Total hits      : %0d",   total_hits);
        $display("  Total misses    : %0d",   total_misses);
        $display("  Hit rate        : %0d%%", total_hits   * 100 / total_accesses);
        $display("  Miss rate       : %0d%%", total_misses * 100 / total_accesses);
        $display("  AMAT formula    : 2 + (miss_rate x 2) cycles");
        $display("  AMAT            : 2 + (%0d%% x 2) = %0d + %0d = %0d cycles",
                  total_misses * 100 / total_accesses,
                  2,
                  (total_misses * 100 / total_accesses) * 2 / 100,
                  2 + (total_misses * 2 / total_accesses));
        $display("============================================================");
        $display("=== Simulation complete ===");
        $stop;
    end

endmodule