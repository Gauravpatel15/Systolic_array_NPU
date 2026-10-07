
`timescale 1ns/1ps

module gemm_tile_scheduler #(
    parameter integer M = 11,
    parameter integer K = 13,
    parameter integer P = 10,

    parameter integer N = 8,
    parameter integer MAX_K = 8,

    parameter integer M_TILES = (M + N - 1) / N,
    parameter integer P_TILES = (P + N - 1) / N,

    parameter integer TILE_ROW_W =
        (M_TILES <= 1) ? 1 : $clog2(M_TILES),

    parameter integer TILE_COL_W =
        (P_TILES <= 1) ? 1 : $clog2(P_TILES),

    parameter integer K_BASE_W =
        (K <= 1) ? 1 : $clog2(K + 1),

    parameter integer TILE_SIZE_W =
        (N <= 1) ? 1 : $clog2(N + 1)
) (
    input  wire                     clk,
    input  wire                     rst,

    input  wire                     start,
    input  wire                     cmd_ready,
    input  wire                     chunk_done,

    output wire                     busy,
    output reg                      done,

    output wire                     cmd_valid,

    output wire [TILE_ROW_W-1:0]    tile_row_index,
    output wire [TILE_COL_W-1:0]    tile_col_index,

    output wire [K_BASE_W-1:0]      k_base,
    output wire [$clog2(MAX_K+1)-1:0] k_length,

    output wire                     accumulate,
    output wire                     first_k_chunk,
    output wire                     last_k_chunk,

    output wire [TILE_SIZE_W-1:0]   valid_rows,
    output wire [TILE_SIZE_W-1:0]   valid_cols
);

    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_COMMAND = 2'd1;
    localparam [1:0] ST_WAIT    = 2'd2;
    localparam [1:0] ST_DONE    = 2'd3;

    reg [1:0] state;

    reg [TILE_ROW_W-1:0] row_counter;
    reg [TILE_COL_W-1:0] col_counter;
    reg [K_BASE_W-1:0]   k_counter;

    assign busy = (state != ST_IDLE) && (state != ST_DONE);

    assign cmd_valid = (state == ST_COMMAND);

    assign tile_row_index = row_counter;
    assign tile_col_index = col_counter;
    assign k_base = k_counter;

    assign k_length =
        ((k_counter + MAX_K) <= K) ?
        MAX_K :
        (K - k_counter);

    assign first_k_chunk = (k_counter == 0);
    assign last_k_chunk = ((k_counter + MAX_K) >= K);

    assign accumulate = !first_k_chunk;

    assign valid_rows =
        ((row_counter * N + N) <= M) ?
        N :
        (M - row_counter * N);

    assign valid_cols =
        ((col_counter * N + N) <= P) ?
        N :
        (P - col_counter * N);

    always @(posedge clk) begin
        if (rst) begin
            state       <= ST_IDLE;
            row_counter <= 0;
            col_counter <= 0;
            k_counter   <= 0;
            done        <= 1'b0;
        end
        else begin
            done <= 1'b0;

            case (state)

                ST_IDLE: begin
                    if (start) begin
                        row_counter <= 0;
                        col_counter <= 0;
                        k_counter   <= 0;
                        state       <= ST_COMMAND;
                    end
                end

                ST_COMMAND: begin
                    if (cmd_ready)
                        state <= ST_WAIT;
                end

                ST_WAIT: begin
                    if (chunk_done) begin

                        if (!last_k_chunk) begin
                            k_counter <= k_counter + MAX_K;
                            state <= ST_COMMAND;
                        end
                        else begin
                            k_counter <= 0;

                            if (col_counter == P_TILES - 1) begin
                                col_counter <= 0;

                                if (row_counter == M_TILES - 1) begin
                                    state <= ST_DONE;
                                end
                                else begin
                                    row_counter <= row_counter + 1'b1;
                                    state <= ST_COMMAND;
                                end
                            end
                            else begin
                                col_counter <= col_counter + 1'b1;
                                state <= ST_COMMAND;
                            end
                        end
                    end
                end

                ST_DONE: begin
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule

