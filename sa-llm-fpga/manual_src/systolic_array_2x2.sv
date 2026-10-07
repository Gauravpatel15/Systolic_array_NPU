
`timescale 1ns/1ps

module systolic_array_2x2 (
    input wire clk,
    input wire rst,
    input wire clear,
    input wire ce,

    input wire signed [7:0] a_row0,
    input wire signed [7:0] a_row1,
    input wire signed [7:0] b_col0,
    input wire signed [7:0] b_col1,

    input wire a_valid_row0,
    input wire a_valid_row1,
    input wire b_valid_col0,
    input wire b_valid_col1,

    output wire signed [31:0] c00,
    output wire signed [31:0] c01,
    output wire signed [31:0] c10,
    output wire signed [31:0] c11
);

    // A moves horizontally.
    wire signed [7:0] a00_to_01;
    wire signed [7:0] a10_to_11;
    wire av00_to_01;
    wire av10_to_11;

    // B moves vertically.
    wire signed [7:0] b00_to_10;
    wire signed [7:0] b01_to_11;
    wire bv00_to_10;
    wire bv01_to_11;

    mac_pe pe00 (
        .clk(clk), .rst(rst), .clear(clear), .ce(ce),

        .a_in(a_row0),
        .b_in(b_col0),
        .a_valid_in(a_valid_row0),
        .b_valid_in(b_valid_col0),

        .a_out(a00_to_01),
        .b_out(b00_to_10),
        .a_valid_out(av00_to_01),
        .b_valid_out(bv00_to_10),

        .acc(c00)
    );

    mac_pe pe01 (
        .clk(clk), .rst(rst), .clear(clear), .ce(ce),

        .a_in(a00_to_01),
        .b_in(b_col1),
        .a_valid_in(av00_to_01),
        .b_valid_in(b_valid_col1),

        .a_out(),
        .b_out(b01_to_11),
        .a_valid_out(),
        .b_valid_out(bv01_to_11),

        .acc(c01)
    );

    mac_pe pe10 (
        .clk(clk), .rst(rst), .clear(clear), .ce(ce),

        .a_in(a_row1),
        .b_in(b00_to_10),
        .a_valid_in(a_valid_row1),
        .b_valid_in(bv00_to_10),

        .a_out(a10_to_11),
        .b_out(),
        .a_valid_out(av10_to_11),
        .b_valid_out(),

        .acc(c10)
    );

    mac_pe pe11 (
        .clk(clk), .rst(rst), .clear(clear), .ce(ce),

        .a_in(a10_to_11),
        .b_in(b01_to_11),
        .a_valid_in(av10_to_11),
        .b_valid_in(bv01_to_11),

        .a_out(),
        .b_out(),
        .a_valid_out(),
        .b_valid_out(),

        .acc(c11)
    );

endmodule

