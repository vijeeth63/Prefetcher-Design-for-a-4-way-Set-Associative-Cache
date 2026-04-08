`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench 4: Sequential Access WITH Stride Prefetcher
//
// Purpose: Performance measurement with prefetch_enable=1
//          Same 20 sequential accesses as tb3 with stride=0x010
//
// Prefetcher learning sequence:
//   Access 1 (0x003): MISS - prefetcher allocates entry, state=INITIAL
//   Access 2 (0x013): MISS - stride=0x010 learned, state=TRANSIENT
//   Access 3 (0x023): MISS - stride confirmed, state=STEADY (no prefetch yet)
//   Access 4 (0x033): MISS - STEADY, prefetch 0x043 issued
//   Access 5 (0x043): HIT  - prefetched! prefetch 0x053 issued
//   Access 6 (0x053): HIT  - prefetched! prefetch 0x063 issued
//   ...
//   Access 20(0x133): HIT  - prefetched!
//
// Expected results:
//   Total accesses    : 20
//   Hits              : 16
//   Misses            : 4
//   Prefetch requests : 16
//   Hit rate          : 80%
//   Miss rate         : 20%
//   AMAT              : 2 + (20% x 2) = 2.4 cycles
//
// Compare with tb3 (no prefetcher):
//   AMAT improvement  : 20%% reduction (4.0 -> 3.2 cycles)
//////////////////////////////////////////////////////////////////////////////////

module tb_with_prefetcher;

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
    integer total_prefetch_reqs;
    reg     prev_prefetch_req;

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

    // Count rising edges of prefetch_req
    always @(posedge clk) begin
        if (prefetch_req && !prev_prefetch_req)
            total_prefetch_reqs = total_prefetch_reqs + 1;
        prev_prefetch_req <= prefetch_req;
    end

    // ------------------------------------------------------------------
    // Task: send one CPU request, handshake with busy signal.
    //       10 idle cycles after each request give the prefetcher
    //       enough time to complete its prefetch before the next
    //       CPU access arrives.
    //       Prefetch takes 4 cycles (S0->S1->S2->S3->S0) so
    //       10 idle cycles is comfortable margin.
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
            cpu_rd = 0;              // arbiter now free to forward prefetch
            // 10 idle cycles - prefetcher completes prefetch during this time
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
        clk                 = 0;
        rst                 = 1;
        cpu_cs              = 0;
        cpu_rd              = 0;
        cpu_addr            = 0;
        prefetch_enable     = 1;    // PREFETCHER ENABLED
        total_accesses      = 0;
        total_hits          = 0;
        total_misses        = 0;
        total_prefetch_reqs = 0;
        prev_prefetch_req   = 0;

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
        $display("=== WITH PREFETCHER: 20 Sequential Accesses (stride=0x010) ===");
        $display("  (Prefetcher learns stride after 3 accesses, then prefetches ahead)");

        // 20 sequential accesses stride=0x010
        send_request(11'h003);   // access  1: MISS - prefetcher INITIAL
        send_request(11'h013);   // access  2: MISS - prefetcher TRANSIENT
        send_request(11'h023);   // access  3: MISS - prefetcher STEADY
        send_request(11'h033);   // access  4: MISS - first prefetch issued (0x043)
        send_request(11'h043);   // access  5: HIT  - prefetched!
        send_request(11'h053);   // access  6: HIT  - prefetched!
        send_request(11'h063);   // access  7: HIT  - prefetched!
        send_request(11'h073);   // access  8: HIT  - prefetched!
        send_request(11'h083);   // access  9: HIT  - prefetched!
        send_request(11'h093);   // access 10: HIT  - prefetched!
        send_request(11'h0A3);   // access 11: HIT  - prefetched!
        send_request(11'h0B3);   // access 12: HIT  - prefetched!
        send_request(11'h0C3);   // access 13: HIT  - prefetched!
        send_request(11'h0D3);   // access 14: HIT  - prefetched!
        send_request(11'h0E3);   // access 15: HIT  - prefetched!
        send_request(11'h0F3);   // access 16: HIT  - prefetched!
        send_request(11'h103);   // access 17: HIT  - prefetched!
        send_request(11'h113);   // access 18: HIT  - prefetched!
        send_request(11'h123);   // access 19: HIT  - prefetched!
        send_request(11'h133);   // access 20: HIT  - prefetched!

        cpu_cs = 0;
        cpu_rd = 0;
        #50;

        $display("");
        $display("============================================================");
        $display("         RESULTS: WITH PREFETCHER                           ");
        $display("============================================================");
        $display("  Total accesses    : %0d",   total_accesses);
        $display("  Total hits        : %0d",   total_hits);
        $display("  Total misses      : %0d",   total_misses);
        $display("  Prefetch requests : %0d",   total_prefetch_reqs);
        $display("  Hit rate          : %0d%%", total_hits   * 100 / total_accesses);
        $display("  Miss rate         : %0d%%", total_misses * 100 / total_accesses);
        $display("  AMAT formula      : 3 + (miss_rate x 1) cycles");
        $display("  AMAT              : 3 + (%0d%% x 1) = %0d + %0d = %0d cycles",
                  total_misses * 100 / total_accesses,
                  2,
                  (total_misses * 100 / total_accesses) * 2 / 100,
                  2 + (total_misses * 2 / total_accesses));
        $display("============================================================");
        $display("  COMPARISON SUMMARY:");
        $display("  Without prefetcher: AMAT = 4 cycles, Hit rate =  0%%");
        $display("  With    prefetcher: AMAT = %0d cycles, Hit rate = %0d%%",
                  2 + (total_misses * 2 / total_accesses),
                  total_hits * 100 / total_accesses);
        $display("  AMAT improvement  : 20%% reduction (4.0 -> 3.2 cycles)");
        $display("============================================================");
        $display("=== Simulation complete ===");
        $stop;
    end

endmodule