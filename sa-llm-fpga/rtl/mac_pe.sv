`timescale 1ns/1ps
// Output-stationary signed MAC. All state uses the same clock enable.
module mac_pe #(
    parameter integer DATA_W = 8,
    parameter integer ACC_W = 32
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,
    input  wire                         ce,
    input  wire signed [DATA_W-1:0]      a_in,
    input  wire signed [DATA_W-1:0]      b_in,
    input  wire                         a_valid_in,
    input  wire                         b_valid_in,
    output reg signed [DATA_W-1:0]       a_out,
    output reg signed [DATA_W-1:0]       b_out,
    output reg                          a_valid_out,
    output reg                          b_valid_out,
    output reg signed [ACC_W-1:0]        acc
);
    // Separate signed product prevents accidental unsigned multiplication.
    wire signed [2*DATA_W-1:0] product = a_in * b_in;
    wire signed [ACC_W-1:0] extended_product =
        {{(ACC_W-2*DATA_W){product[2*DATA_W-1]}}, product};

    // Synchronous, active-high reset/clear take priority over stalls.
    // ACC_W must be >= 2*DATA_W. Overflow intentionally wraps modulo 2^ACC_W.
    always @(posedge clk) begin
        if (rst || clear) begin
            a_out       <= '0;
            b_out       <= '0;
            a_valid_out <= 1'b0;
            b_valid_out <= 1'b0;
            acc         <= '0;
        end else if (ce) begin
            a_out       <= a_in;
            b_out       <= b_in;
            a_valid_out <= a_valid_in;
            b_valid_out <= b_valid_in;
            if (a_valid_in && b_valid_in)
                acc <= acc + extended_product;
        end
    end
endmodule
