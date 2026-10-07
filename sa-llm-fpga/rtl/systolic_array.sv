`timescale 1ns/1ps
// Arithmetic core only: caller supplies skewed boundary data and completion timing.
module systolic_array #(
    parameter integer N = 2,
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,
    input  wire                         ce,
    input  wire [N*DATA_W-1:0]           a_left,
    input  wire [N*DATA_W-1:0]           b_top,
    input  wire [N-1:0]                  a_valid_left,
    input  wire [N-1:0]                  b_valid_top,
    output wire [N*N*ACC_W-1:0]          c_flat
);
    wire signed [DATA_W-1:0] a [0:N-1][0:N];
    wire signed [DATA_W-1:0] b [0:N][0:N-1];
    wire av [0:N-1][0:N];
    wire bv [0:N][0:N-1];
    genvar r, c;
    generate
        for (r=0; r<N; r=r+1) begin : rows
            assign a[r][0] = a_left[r*DATA_W +: DATA_W];
            assign av[r][0] = a_valid_left[r];
            for (c=0; c<N; c=c+1) begin : cols
                mac_pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) pe (
                    .clk(clk), .rst(rst), .clear(clear), .ce(ce),
                    .a_in(a[r][c]), .b_in(b[r][c]),
                    .a_valid_in(av[r][c]), .b_valid_in(bv[r][c]),
                    .a_out(a[r][c+1]), .b_out(b[r+1][c]),
                    .a_valid_out(av[r][c+1]), .b_valid_out(bv[r+1][c]),
                    .acc(c_flat[(r*N+c)*ACC_W +: ACC_W])
                );
            end
        end
        for (c=0; c<N; c=c+1) begin : top_boundary
            assign b[0][c] = b_top[c*DATA_W +: DATA_W];
            assign bv[0][c] = b_valid_top[c];
        end
    endgenerate
endmodule
