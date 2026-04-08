`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: cache_4way
// Description: 4-way set associative cache
//              16 sets, 4 ways per set, 16 words per block, 32 bits per word
//              Compatible with 128-block RAM
//              LRU replacement policy (0=MRU, 3=LRU)
//              busy output for prefetcher/arbiter integration
//////////////////////////////////////////////////////////////////////////////////

module cache_4way(
    input         clk,
    input         rst,
    input         cs,
    input         rd,
    input  [10:0] addr,
    output reg [31:0] data_out,
    output reg    hit,
    output        busy
);
    // Address breakdown
    wire [2:0] addr_tag   = addr[10:8];
    wire [3:0] set_index  = addr[7:4];
    wire [3:0] block_off  = addr[3:0];

    // FSM state encoding
    parameter S0 = 2'b00;  // IDLE
    parameter S1 = 2'b01;  // CHECK
    parameter S2 = 2'b10;  // FETCH
    parameter S3 = 2'b11;  // FILL

    reg [1:0] current_state, next_state;
    assign busy = (current_state != S0);

    // Cache storage
    reg [31:0] cache_data [0:15][0:3][0:15];
    reg [2:0]  tag_array  [0:15][0:3];
    reg        valid      [0:15][0:3];
    reg [1:0]  lru        [0:15][0:3];

    // RAM interface
    reg         ram_cs, ram_rd;
    reg  [10:0] ram_addr;
    wire [511:0] ram_data_out;

    ram ram_inst (
        .clk     (clk),
        .cs      (ram_cs),
        .rd      (ram_rd),
        .wr      (1'b0),
        .addr    (ram_addr),
        .data_in (32'b0),
        .data_out(ram_data_out)
    );

    reg [1:0] victim_way;
    reg [1:0] hit_way;
    reg [1:0] victim_way_c;
    reg       found_invalid;
    integer   ii;

    always @(*) begin
        // defaults
        hit           = 1'b0;
        hit_way       = 2'b00;
        found_invalid = 1'b0;
        victim_way_c  = 2'b00;
        ram_cs        = 1'b0;
        ram_rd        = 1'b0;
        ram_addr      = 11'b0;
        next_state    = current_state;

        // --- Hit detection ---
        if (cs && rd) begin
            for (ii = 0; ii < 4; ii = ii + 1) begin
                if (valid[set_index][ii] && tag_array[set_index][ii] == addr_tag) begin
                    hit     = 1'b1;
                    hit_way = ii[1:0];
                end
            end
        end

        // --- Victim selection ---
        for (ii = 0; ii < 4; ii = ii + 1) begin
            if (!found_invalid && !valid[set_index][ii]) begin
                victim_way_c  = ii[1:0];
                found_invalid = 1'b1;
            end
        end
        if (!found_invalid) begin
            for (ii = 0; ii < 4; ii = ii + 1) begin
                if (lru[set_index][ii] == 2'd3)
                    victim_way_c = ii[1:0];
            end
        end

        // --- FSM next state and RAM control ---
        case (current_state)
            S0: next_state = (cs && rd) ? S1 : S0;
            S1: next_state = hit ? S0 : S2;
            S2: begin
                ram_cs   = 1'b1;
                ram_rd   = 1'b1;
                ram_addr = {addr_tag, set_index, 4'b0000};
                next_state = S3;
            end
            S3: next_state = S0;
            default: next_state = S0;
        endcase
    end

    integer i, k;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= S0;
            for (i = 0; i < 16; i = i + 1) begin
                valid[i][0] <= 1'b0;
                valid[i][1] <= 1'b0;
                valid[i][2] <= 1'b0;
                valid[i][3] <= 1'b0;
                lru[i][0]   <= 2'd0;
                lru[i][1]   <= 2'd0;
                lru[i][2]   <= 2'd0;
                lru[i][3]   <= 2'd0;
            end
        end else begin
            current_state <= next_state;

            // -----------------------------------------------------------------
            // S1: HIT - return data, update LRU
            // -----------------------------------------------------------------
            if (current_state == S1 && hit) begin
                data_out <= cache_data[set_index][hit_way][block_off];
                
                // FIXED: Only increment ways more recently used than hit_way
                for (i = 0; i < 4; i = i + 1) begin
                    if (i[1:0] != hit_way && valid[set_index][i]) begin
                        if (lru[set_index][i] < lru[set_index][hit_way])
                            lru[set_index][i] <= lru[set_index][i] + 1;
                    end
                end
                lru[set_index][hit_way] <= 2'd0;
            end

            // -----------------------------------------------------------------
            // S2: latch victim way
            // -----------------------------------------------------------------
            if (current_state == S2) begin
                victim_way <= victim_way_c;
            end

            // -----------------------------------------------------------------
            // S3: FILL - write RAM block into cache, update LRU
            // -----------------------------------------------------------------
            if (current_state == S3) begin
                for (k = 0; k < 16; k = k + 1)
                    cache_data[set_index][victim_way][k] <= ram_data_out[k*32 +: 32];
                
                tag_array[set_index][victim_way] <= addr_tag;
                valid[set_index][victim_way]     <= 1'b1;
                data_out <= ram_data_out[block_off*32 +: 32];
                
                for (i = 0; i < 4; i = i + 1) begin
                    if (i[1:0] != victim_way && valid[set_index][i]) begin
                        if (lru[set_index][i] != 2'd3)
                            lru[set_index][i] <= lru[set_index][i] + 1;
                    end
                end
                lru[set_index][victim_way] <= 2'd0;
            end
        end
    end

endmodule