`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: top
// Description: Top-level module integrating:
//                1. stride_prefetcher  - detects stride patterns, generates prefetch requests
//                2. arbiter            - prioritises CPU over prefetcher for cache access
//                3. cache_4way         - 4-way set associative L1 cache
//                4. ram                - instantiated inside cache_4way
//
// Signal flow (prefetch_enable = 1):
//   CPU (testbench) --> arbiter --> cache_4way --> ram
//                          ^
//   stride_prefetcher -----+
//
// Signal flow (prefetch_enable = 0):
//   CPU (testbench) --> cache_4way --> ram
//   (arbiter and prefetcher are bypassed)
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Added prefetch_enable input for before/after comparison
//////////////////////////////////////////////////////////////////////////////////

module top(
    input         clk,
    input         rst,

    // --- CPU interface (driven by testbench) ---
    input         cpu_cs,
    input         cpu_rd,
    input  [10:0] cpu_addr,

    // --- Prefetcher enable (1 = with prefetcher, 0 = bypass prefetcher) ---
    input         prefetch_enable,

    // --- Outputs back to CPU (testbench) ---
    output [31:0] data_out,
    output        hit,
    output        busy,

    // --- Prefetch observability (for testbench statistics) ---
    output        prefetch_req
);

    // -------------------------------------------------------------------------
    // Internal wires
    // -------------------------------------------------------------------------

    wire [10:0] prefetch_addr;
    wire        prefetch_req_int;

    wire [10:0] arb_cache_addr;
    wire        arb_cache_cs;
    wire        arb_cache_rd;

    // Final signals into cache - selected by prefetch_enable
    wire [10:0] cache_addr;
    wire        cache_cs;
    wire        cache_rd;

    // -------------------------------------------------------------------------
    // prefetch_req exposed to testbench only when enabled
    // -------------------------------------------------------------------------
    assign prefetch_req = prefetch_enable ? prefetch_req_int : 1'b0;

    // -------------------------------------------------------------------------
    // Module 1: Stride Prefetcher
    // -------------------------------------------------------------------------
    stride_prefetcher prefetcher_inst (
        .clk          (clk),
        .rst          (rst),
        .cpu_addr     (cpu_addr),
        .cs           (cpu_cs),
        .rd           (cpu_rd),
        .busy         (busy),
        .prefetch_addr(prefetch_addr),
        .prefetch_req (prefetch_req_int)
    );

    // -------------------------------------------------------------------------
    // Module 2: Arbiter
    // -------------------------------------------------------------------------
    arbiter arbiter_inst (
        .cpu_addr     (cpu_addr),
        .cpu_cs       (cpu_cs),
        .cpu_rd       (cpu_rd),
        .prefetch_addr(prefetch_addr),
        .prefetch_req (prefetch_req_int),
        .busy         (busy),
        .cache_addr   (arb_cache_addr),
        .cache_cs     (arb_cache_cs),
        .cache_rd     (arb_cache_rd)
    );

    // -------------------------------------------------------------------------
    // Mux: prefetch_enable=1 -> arbiter drives cache
    //      prefetch_enable=0 -> CPU drives cache directly
    // -------------------------------------------------------------------------
    assign cache_addr = prefetch_enable ? arb_cache_addr : cpu_addr;
    assign cache_cs   = prefetch_enable ? arb_cache_cs   : cpu_cs;
    assign cache_rd   = prefetch_enable ? arb_cache_rd   : cpu_rd;

    // -------------------------------------------------------------------------
    // Module 3: Cache (instantiates RAM internally)
    // -------------------------------------------------------------------------
    cache_4way cache_inst (
        .clk      (clk),
        .rst      (rst),
        .cs       (cache_cs),
        .rd       (cache_rd),
        .addr     (cache_addr),
        .data_out (data_out),
        .hit      (hit),
        .busy     (busy)
    );

endmodule