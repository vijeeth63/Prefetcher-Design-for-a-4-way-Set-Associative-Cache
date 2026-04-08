`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.01.2026 18:35:48
// Design Name: 
// Module Name: ram_memory
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: RAM with 128 blocks, 16 words per block, 32 bits per word
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Scaled to 128 blocks
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ram (clk, cs, rd, wr, addr, data_in, data_out
    );
    input cs, rd, wr, clk;
    input [10:0] addr;
    input [31:0] data_in;
    output reg [511:0] data_out;
    integer i;
    
    reg [31:0] mem[0:127][0:15];
    wire [6:0] line_addr;
    wire [3:0] word_offset;

    assign line_addr  = addr[10:4];
    assign word_offset = addr[3:0];
    
    always @ (posedge clk) begin
        if ( cs && wr && !rd ) begin
            mem[line_addr][word_offset]<=data_in;
            
        end
        else if (cs && rd && !wr)begin
            for (i = 0; i < 16; i = i + 1) begin
                data_out[i*32 +: 32] <= mem[line_addr][i];
            end
        end

    end
endmodule