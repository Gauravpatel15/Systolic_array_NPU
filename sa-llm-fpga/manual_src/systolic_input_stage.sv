
`timescale 1ns/1ps

module systolic_input_stage #(
    parameter integer N = 8,
    parameter integer DATA_W = 8
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     clear,

    // Controller says that this clock requests a buffer read.
    input  wire                     read_step_enable,

    input  wire [N-1:0]             a_read_valid,
    input  wire [N-1:0]             b_read_valid,

    // These values come directly from synchronous buffer outputs.
    input  wire [N*DATA_W-1:0]      a_data_from_buffer,
    input  wire [N*DATA_W-1:0]      b_data_from_buffer,

    // These signals drive the systolic array.
    output reg                      array_ce,
    output reg [N-1:0]              a_valid_to_array,
    output reg [N-1:0]              b_valid_to_array,

    output wire [N*DATA_W-1:0]      a_data_to_array,
    output wire [N*DATA_W-1:0]      b_data_to_array
);

    // Buffer outputs are already registered by tile_bank.
    // Only CE and valid signals need a one-clock pipeline delay.
    assign a_data_to_array = a_data_from_buffer;
    assign b_data_to_array = b_data_from_buffer;

    always @(posedge clk) begin
        if (rst || clear) begin
            array_ce        <= 1'b0;
            a_valid_to_array <= {N{1'b0}};
            b_valid_to_array <= {N{1'b0}};
        end
        else begin
            array_ce <= read_step_enable;

            if (read_step_enable) begin
                a_valid_to_array <= a_read_valid;
                b_valid_to_array <= b_read_valid;
            end
            else begin
                a_valid_to_array <= {N{1'b0}};
                b_valid_to_array <= {N{1'b0}};
            end
        end
    end

endmodule

