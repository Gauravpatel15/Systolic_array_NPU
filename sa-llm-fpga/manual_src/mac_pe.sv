
`timescale 1ns/1ps

module mac_pe (
    input  wire clk,
    input  wire rst,
    input  wire clear,
    input  wire ce,

    input  wire signed [7:0] a_in,
    input  wire signed [7:0] b_in,

    input  wire a_valid_in,
    input  wire b_valid_in,

    output reg signed [7:0] a_out,
    output reg signed [7:0] b_out,

    output reg a_valid_out,
    output reg b_valid_out,

    output reg signed [31:0] acc
);

    // Tell Vivado to implement this multiplier with a DSP48 block.
    (* use_dsp = "yes" *)
    wire signed [15:0] product;

    wire signed [31:0] product_extended;

    assign product = a_in * b_in;

    assign product_extended = {{16{product[15]}}, product};

    always @(posedge clk) begin
        if (rst || clear) begin
            a_out       <= 8'sd0;
            b_out       <= 8'sd0;
            a_valid_out <= 1'b0;
            b_valid_out <= 1'b0;
            acc         <= 32'sd0;
        end
        else if (ce) begin
            a_out       <= a_in;
            b_out       <= b_in;
            a_valid_out <= a_valid_in;
            b_valid_out <= b_valid_in;

            if (a_valid_in && b_valid_in)
                acc <= acc + product_extended;
        end
    end

endmodule

