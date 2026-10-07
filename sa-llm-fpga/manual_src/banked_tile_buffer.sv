
`timescale 1ns/1ps

module banked_tile_buffer #(
    parameter integer N = 8,
    parameter integer MAX_K = 8,
    parameter integer DATA_W = 8,
    parameter integer ADDR_W = $clog2(MAX_K),
    parameter integer BANK_W = $clog2(N)
) (
    input  wire                         clk,
    input  wire                         rst,

    // One bank is loaded at a time in this first version.
    input  wire                         load_write_enable,
    input  wire [BANK_W-1:0]            load_bank,
    input  wire [ADDR_W-1:0]            load_addr,
    input  wire signed [DATA_W-1:0]     load_data,

    // All N banks can read in parallel.
    input  wire [N-1:0]                 read_enable,
    input  wire [N*ADDR_W-1:0]          read_addr,

    output wire [N*DATA_W-1:0]          read_data
);

    genvar bank;

    generate
        for (bank = 0; bank < N; bank = bank + 1) begin : gen_banks

            tile_bank #(
                .DATA_W(DATA_W),
                .DEPTH(MAX_K)
            ) bank_memory (
                .clk(clk),
                .rst(rst),

                .write_enable(
                    load_write_enable && (load_bank == bank)
                ),
                .write_addr(load_addr),
                .write_data(load_data),

                .read_enable(read_enable[bank]),
                .read_addr(
                    read_addr[bank*ADDR_W +: ADDR_W]
                ),
                .read_data(
                    read_data[bank*DATA_W +: DATA_W]
                )
            );

        end
    endgenerate

endmodule

