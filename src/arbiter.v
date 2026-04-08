`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: arbiter
// Description: Priority arbiter between CPU and stride prefetcher.
//              Decides which requester gets access to the cache at any cycle.
//
// Priority Rules:
//   1. CPU always has higher priority than the prefetcher.
//   2. Prefetcher gets access only when:
//        - CPU is NOT making a request (cs=0 or rd=0), AND
//        - Prefetcher has a pending request (prefetch_req=1)
//   3. If neither is requesting, cache inputs are driven to 0 (idle).
//
// This module is purely combinational - no clock or FSM needed.
//////////////////////////////////////////////////////////////////////////////////

module arbiter(
    // --- CPU side ---
    input  [10:0] cpu_addr,       // address from CPU
    input         cpu_cs,         // chip select from CPU
    input         cpu_rd,         // read signal from CPU

    // --- Prefetcher side ---
    input  [10:0] prefetch_addr,  // predicted address from stride_prefetcher
    input         prefetch_req,   // HIGH when prefetcher has a pending request

    // --- Cache status ---
    input         busy,           // HIGH when cache is busy (from cache_4way)

    // --- Outputs to cache ---
    output reg [10:0] cache_addr, // address forwarded to cache
    output reg        cache_cs,   // chip select forwarded to cache
    output reg        cache_rd    // read signal forwarded to cache
);

    always @(*) begin
        if (cpu_cs && cpu_rd) begin
            // CPU is requesting - give it full priority
            cache_addr = cpu_addr;
            cache_cs   = 1'b1;
            cache_rd   = 1'b1;
        end else if (prefetch_req) begin 
            // CPU is idle, prefetcher has a request
            // - hand the cache to the prefetcher
            cache_addr = prefetch_addr;
            cache_cs   = 1'b1;
            cache_rd   = 1'b1;
        end else begin
            // Nothing to do - keep cache idle
            cache_addr = 11'b0;
            cache_cs   = 1'b0;
            cache_rd   = 1'b0;
        end
    end

endmodule