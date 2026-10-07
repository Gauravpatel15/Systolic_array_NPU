
`timescale 1ns/1ps

module compact_tiled_gemm_top #(
    parameter integer M = 11,
    parameter integer K = 13,
    parameter integer P = 10,

    parameter integer N = 8,
    parameter integer MAX_K = 8,
    parameter integer DATA_W = 8,

    parameter integer A_MEM_ADDR_W =
        ((M*K) <= 1) ? 1 : $clog2(M*K),

    parameter integer B_MEM_ADDR_W =
        ((K*P) <= 1) ? 1 : $clog2(K*P),

    parameter integer C_MEM_ADDR_W =
        ((M*P) <= 1) ? 1 : $clog2(M*P),

    parameter integer TILE_ROW_W =
        (((M + N - 1) / N) <= 1) ? 1 : $clog2((M + N - 1) / N),

    parameter integer TILE_COL_W =
        (((P + N - 1) / N) <= 1) ? 1 : $clog2((P + N - 1) / N),

    parameter integer TILE_SIZE_W =
        (N <= 1) ? 1 : $clog2(N + 1),

    parameter integer BANK_W =
        (N <= 1) ? 1 : $clog2(N)
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         start,
    input  wire                         stall,

    output wire                         busy,
    output reg                          done,
    output wire                         error,

    // A and B external memory read ports.
    output wire [A_MEM_ADDR_W-1:0]      a_mem_addr,
    input  wire signed [DATA_W-1:0]     a_mem_data,

    output wire [B_MEM_ADDR_W-1:0]      b_mem_addr,
    input  wire signed [DATA_W-1:0]     b_mem_data,

    // C external memory write port.
    output wire                         c_write_enable,
    output wire [C_MEM_ADDR_W-1:0]      c_write_addr,
    output wire signed [31:0]           c_write_data
);

    wire system_busy;
    wire system_done;
    wire system_error;

    wire system_result_valid;
    wire [TILE_ROW_W-1:0] system_tile_row;
    wire [TILE_COL_W-1:0] system_tile_col;
    wire [TILE_SIZE_W-1:0] system_valid_rows;
    wire [TILE_SIZE_W-1:0] system_valid_cols;
    wire [N*N*32-1:0] system_result_tile;

    reg write_active;
    reg done_pending;

    reg [TILE_ROW_W-1:0] saved_tile_row;
    reg [TILE_COL_W-1:0] saved_tile_col;
    reg [TILE_SIZE_W-1:0] saved_valid_rows;
    reg [TILE_SIZE_W-1:0] saved_valid_cols;

    reg [N*N*32-1:0] saved_result_tile;

    reg [BANK_W-1:0] write_row;
    reg [BANK_W-1:0] write_col;

    assign c_write_enable = write_active;

    assign c_write_addr =
        (saved_tile_row * N + write_row) * P +
        saved_tile_col * N + write_col;

    assign c_write_data =
        $signed(saved_result_tile[
            (write_row*N + write_col)*32 +: 32
        ]);

    assign busy =
        system_busy ||
        write_active ||
        done_pending;

    assign error = system_error;

    tiled_gemm_system #(
        .M(M),
        .K(K),
        .P(P),
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) system_core (
        .clk(clk),
        .rst(rst),

        .start(start),
        .stall(stall),

        .busy(system_busy),
        .done(system_done),
        .error(system_error),

        .a_mem_addr(a_mem_addr),
        .a_mem_data(a_mem_data),

        .b_mem_addr(b_mem_addr),
        .b_mem_data(b_mem_data),

        .result_valid(system_result_valid),
        .result_tile_row(system_tile_row),
        .result_tile_col(system_tile_col),
        .result_valid_rows(system_valid_rows),
        .result_valid_cols(system_valid_cols),
        .result_tile(system_result_tile)
    );

    always @(posedge clk) begin
        if (rst) begin
            write_active <= 1'b0;
            done_pending <= 1'b0;
            done <= 1'b0;

            saved_tile_row <= 0;
            saved_tile_col <= 0;
            saved_valid_rows <= 0;
            saved_valid_cols <= 0;
            saved_result_tile <= 0;

            write_row <= 0;
            write_col <= 0;
        end
        else begin
            done <= 1'b0;

            // Capture one complete N x N result tile.
            if (system_result_valid && !write_active) begin
                saved_tile_row <= system_tile_row;
                saved_tile_col <= system_tile_col;
                saved_valid_rows <= system_valid_rows;
                saved_valid_cols <= system_valid_cols;
                saved_result_tile <= system_result_tile;

                write_row <= 0;
                write_col <= 0;
                write_active <= 1'b1;
            end

            // Stream one valid C element to external memory every cycle.
            else if (write_active) begin
                if ((write_row == saved_valid_rows - 1) &&
                    (write_col == saved_valid_cols - 1)) begin

                    write_active <= 1'b0;
                end
                else if (write_col == saved_valid_cols - 1) begin
                    write_col <= 0;
                    write_row <= write_row + 1'b1;
                end
                else begin
                    write_col <= write_col + 1'b1;
                end
            end

            // Wait until final C tile has fully streamed out.
            if (system_done)
                done_pending <= 1'b1;

            if (done_pending && !write_active) begin
                done <= 1'b1;
                done_pending <= 1'b0;
            end
        end
    end

endmodule

