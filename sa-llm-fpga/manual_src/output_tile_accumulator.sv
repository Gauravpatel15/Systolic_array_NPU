
`timescale 1ns/1ps

module output_tile_accumulator #(
    parameter integer N = 8
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     clear,

    input  wire                     write_enable,
    input  wire                     accumulate,

    input  wire [N*N*32-1:0]        tile_result,
    output reg  [N*N*32-1:0]        c_tile
);

    integer i;

    always @(posedge clk) begin
        if (rst || clear) begin
            c_tile <= {N*N*32{1'b0}};
        end
        else if (write_enable) begin
            for (i = 0; i < N*N; i = i + 1) begin
                if (accumulate) begin
                    c_tile[i*32 +: 32] <=
                        $signed(c_tile[i*32 +: 32]) +
                        $signed(tile_result[i*32 +: 32]);
                end
                else begin
                    c_tile[i*32 +: 32] <=
                        tile_result[i*32 +: 32];
                end
            end
        end
    end

endmodule

