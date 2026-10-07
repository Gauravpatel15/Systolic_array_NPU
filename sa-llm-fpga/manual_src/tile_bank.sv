
`timescale 1ns/1ps

module tile_bank #(
    parameter integer DATA_W = 8,
    parameter integer DEPTH = 8,
    parameter integer ADDR_W = $clog2(DEPTH)
) (
    input  wire                     clk,
    input  wire                     rst,

    input  wire                     write_enable,
    input  wire [ADDR_W-1:0]        write_addr,
    input  wire signed [DATA_W-1:0] write_data,

    input  wire                     read_enable,
    input  wire [ADDR_W-1:0]        read_addr,
    output reg signed [DATA_W-1:0]  read_data
);

    reg signed [DATA_W-1:0] memory [0:DEPTH-1];

    always @(posedge clk) begin
        if (rst) begin
            // Reset only the output register.
            // FPGA BRAM contents are not cleared here.
            read_data <= {DATA_W{1'b0}};
        end
        else begin
            if (write_enable)
                memory[write_addr] <= write_data;

            if (read_enable)
                read_data <= memory[read_addr];
        end
    end

endmodule

