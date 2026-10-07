
`timescale 1ns/1ps

module systolic_array #(
    parameter integer N = 2
) (
    input wire clk,
    input wire rst,
    input wire clear,
    input wire ce,

    input wire [N*8-1:0] a_left,
    input wire [N*8-1:0] b_top,

    input wire [N-1:0] a_valid_left,
    input wire [N-1:0] b_valid_top,

    output wire [N*N*32-1:0] c_flat
);

    // Horizontal connections for A.
    wire signed [7:0] a_bus [0:N-1][0:N];
    wire a_valid_bus [0:N-1][0:N];

    // Vertical connections for B.
    wire signed [7:0] b_bus [0:N][0:N-1];
    wire b_valid_bus [0:N][0:N-1];

    genvar r, c;

    generate
        for (r = 0; r < N; r = r + 1) begin : rows

            // Connect the external A input for this row.
            assign a_bus[r][0] = a_left[r*8 +: 8];
            assign a_valid_bus[r][0] = a_valid_left[r];

            for (c = 0; c < N; c = c + 1) begin : cols

                mac_pe pe (
                    .clk(clk),
                    .rst(rst),
                    .clear(clear),
                    .ce(ce),

                    .a_in(a_bus[r][c]),
                    .b_in(b_bus[r][c]),

                    .a_valid_in(a_valid_bus[r][c]),
                    .b_valid_in(b_valid_bus[r][c]),

                    .a_out(a_bus[r][c+1]),
                    .b_out(b_bus[r+1][c]),

                    .a_valid_out(a_valid_bus[r][c+1]),
                    .b_valid_out(b_valid_bus[r+1][c]),

                    .acc(c_flat[(r*N+c)*32 +: 32])
                );

            end
        end

        for (c = 0; c < N; c = c + 1) begin : top_inputs

            // Connect the external B input for this column.
            assign b_bus[0][c] = b_top[c*8 +: 8];
            assign b_valid_bus[0][c] = b_valid_top[c];

        end
    endgenerate

endmodule

