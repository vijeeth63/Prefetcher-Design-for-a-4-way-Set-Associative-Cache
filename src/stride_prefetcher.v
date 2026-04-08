`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: stride_prefetcher
// Description: 4-entry stride prefetcher
//              Watches CPU memory accesses, detects constant stride patterns,
//              and issues early prefetch requests to the cache via the arbiter.
//
// Entry States:
//   INITIAL   - Entry allocated, first address stored, stride unknown
//   TRANSIENT - One stride observed, waiting for confirmation
//   STEADY    - Stride confirmed, actively issuing prefetch requests
//
// Replacement Policy: Round Robin (when all 4 entries are occupied)
// Pending Prefetch  : New prefetch suppressed if one is already pending
//                     (standard practice - do not overwrite pending request)
//////////////////////////////////////////////////////////////////////////////////

module stride_prefetcher(
    input             clk,
    input             rst,
    input  [10:0]     cpu_addr,      // address from CPU
    input             cs,            // chip select from CPU
    input             rd,            // read signal from CPU
    input             busy,          // HIGH when cache is busy (from cache_4way)
    output reg [10:0] prefetch_addr, // predicted next address to prefetch
    output reg        prefetch_req   // HIGH when prefetcher has a request pending
);
    // -------------------------------------------------------------------------
    // State encoding
    // -------------------------------------------------------------------------
    parameter INITIAL   = 2'b00;
    parameter TRANSIENT = 2'b01;
    parameter STEADY    = 2'b10;

    // -------------------------------------------------------------------------
    // 4-entry prefetcher table
    // -------------------------------------------------------------------------
    reg [10:0]        prev_addr [0:3];     // last address seen in this stream
    reg signed [11:0] stride    [0:3];     // detected stride (signed, 12-bit covers +/-2047)
    reg [1:0]         state     [0:3];     // INITIAL / TRANSIENT / STEADY
    reg               valid     [0:3];     // is this entry occupied?

    // Round robin replacement pointer
    reg [1:0] rr_ptr;

    // -------------------------------------------------------------------------
    // Temporary (local) variables
    // -------------------------------------------------------------------------
    integer i;
    reg        matched;
    reg [1:0]  match_idx;
    reg signed [11:0] delta;
    reg        found_free;
    reg [1:0]  alloc_idx;
    reg signed [11:0] predicted;
    
    // Edge detection and handshake registers
    reg        prev_cs;
    reg        wait_for_busy; 

    // -------------------------------------------------------------------------
    // Main sequential logic
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i]     <= 1'b0;
                state[i]     <= INITIAL;
                prev_addr[i] <= 11'b0;
                stride[i]    <= 12'b0;
            end
            rr_ptr        <= 2'b00;
            prefetch_addr <= 11'b0;
            prefetch_req  <= 1'b0;
            prev_cs       <= 1'b0; 
            wait_for_busy <= 1'b0; 

        end else begin

            // Update the tracking register every clock cycle
            prev_cs <= cs;

            // -----------------------------------------------------------------
            // Handshake logic: Clear prefetch_req once the cache has FULLY finished
            // -----------------------------------------------------------------
            if (prefetch_req) begin
                if (wait_for_busy) begin
                    // Wait until the cache actually starts our prefetch.
                    if (busy && !cs) begin
                        wait_for_busy <= 1'b0;
                    end
                end else begin
                    // Cache has started, now wait for it to finish
                    if (!busy) begin
                        prefetch_req <= 1'b0;
                    end
                end
            end

            // -----------------------------------------------------------------
            // Only process on the RISING EDGE of the CPU read request
            // -----------------------------------------------------------------
            if (cs && rd && !prev_cs) begin

                // Step 1: Search for a matching TRANSIENT or STEADY entry.
                matched   = 1'b0;
                match_idx = 2'b00;

                for (i = 0; i < 4; i = i + 1) begin
                    if (!matched && valid[i] &&
                        (state[i] == TRANSIENT || state[i] == STEADY)) begin
                        delta = $signed({1'b0, cpu_addr}) - $signed({1'b0, prev_addr[i]});
                        if (delta == stride[i]) begin
                            matched   = 1'b1;
                            match_idx = i[1:0];
                        end
                    end
                end

                // Step 2: If no TRANSIENT/STEADY match, try an INITIAL entry.
                if (!matched) begin
                    for (i = 0; i < 4; i = i + 1) begin
                        if (!matched && valid[i] && state[i] == INITIAL) begin
                            matched   = 1'b1;
                            match_idx = i[1:0];
                        end
                    end
                end

                // Step 3: Update matched entry, or allocate a new one
                if (matched) begin
                    delta = $signed({1'b0, cpu_addr}) - $signed({1'b0, prev_addr[match_idx]});

                    case (state[match_idx])
                        INITIAL: begin
                            stride[match_idx]    <= delta;
                            state[match_idx]     <= TRANSIENT;
                            prev_addr[match_idx] <= cpu_addr;
                        end
                        TRANSIENT: begin
                            if (delta == stride[match_idx]) begin
                                state[match_idx] <= STEADY;
                            end else begin
                                stride[match_idx] <= delta;
                            end
                            prev_addr[match_idx] <= cpu_addr;
                        end
                        STEADY: begin
                            if (delta == stride[match_idx]) begin
                                if (!prefetch_req) begin
                                    predicted     = $signed({1'b0, cpu_addr}) + stride[match_idx];
                                    prefetch_addr <= predicted[10:0];
                                    prefetch_req  <= 1'b1;
                                    wait_for_busy <= 1'b1; // Start the handshake
                                end
                            end else begin
                                stride[match_idx] <= delta;
                                state[match_idx]  <= TRANSIENT;
                            end
                            prev_addr[match_idx] <= cpu_addr;
                        end
                        default: begin
                            prev_addr[match_idx] <= cpu_addr;
                        end
                    endcase

                end else begin
                    // No match - allocate a fresh entry
                    found_free = 1'b0;
                    alloc_idx  = rr_ptr; 

                    for (i = 0; i < 4; i = i + 1) begin
                        if (!found_free && !valid[i]) begin
                            alloc_idx  = i[1:0];
                            found_free = 1'b1;
                        end
                    end

                    valid[alloc_idx]     <= 1'b1;
                    prev_addr[alloc_idx] <= cpu_addr;
                    stride[alloc_idx]    <= 12'b0;
                    state[alloc_idx]     <= INITIAL;

                    if (!found_free) begin
                        rr_ptr <= rr_ptr + 1;
                    end
                end
            end // cs && rd && !prev_cs
        end // else (not rst)
    end // always
endmodule