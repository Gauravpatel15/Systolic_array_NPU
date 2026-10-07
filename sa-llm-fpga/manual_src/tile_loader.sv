
`timescale 1ns/1ps

module tile_loader #(
    parameter integer M = 11,
    parameter integer K = 13,
    parameter integer P = 10,

    parameter integer N = 8,
    parameter integer MAX_K = 8,
    parameter integer DATA_W = 8,

    parameter integer ADDR_W =
        (MAX_K <= 1) ? 1 : $clog2(MAX_K),

    parameter integer BANK_W =
        (N <= 1) ? 1 : $clog2(N),

    parameter integer TILE_ROW_W =
        (((M + N - 1) / N) <= 1) ? 1 : $clog2((M + N - 1) / N),

    parameter integer TILE_COL_W =
        (((P + N - 1) / N) <= 1) ? 1 : $clog2((P + N - 1) / N),

    parameter integer K_BASE_W =
        (K <= 1) ? 1 : $clog2(K + 1),

    parameter integer LEN_W =
        $clog2(MAX_K + 1),

    parameter integer TILE_SIZE_W =
        (N <= 1) ? 1 : $clog2(N + 1),

    parameter integer A_MEM_ADDR_W =
        ((M*K) <= 1) ? 1 : $clog2(M*K),

    parameter integer B_MEM_ADDR_W =
        ((K*P) <= 1) ? 1 : $clog2(K*P)
) (
    input  wire                         clk,
    input  wire                         rst,

    // Command from gemm_tile_scheduler.
    input  wire                         cmd_valid,
    output wire                         cmd_ready,

    input  wire [TILE_ROW_W-1:0]        tile_row_index,
    input  wire [TILE_COL_W-1:0]        tile_col_index,
    input  wire [K_BASE_W-1:0]          k_base,
    input  wire [LEN_W-1:0]             k_length,
    input  wire [TILE_SIZE_W-1:0]       valid_rows,
    input  wire [TILE_SIZE_W-1:0]       valid_cols,

    // Combinational external matrix-memory read ports.
    output wire [A_MEM_ADDR_W-1:0]      a_mem_addr,
    input  wire signed [DATA_W-1:0]     a_mem_data,

    output wire [B_MEM_ADDR_W-1:0]      b_mem_addr,
    input  wire signed [DATA_W-1:0]     b_mem_data,

    // Serial write interface for activation buffer.
    output wire                         a_load_write_enable,
    output wire [BANK_W-1:0]            a_load_bank,
    output wire [ADDR_W-1:0]            a_load_addr,
    output wire signed [DATA_W-1:0]     a_load_data,

    // Serial write interface for weight buffer.
    output wire                         b_load_write_enable,
    output wire [BANK_W-1:0]            b_load_bank,
    output wire [ADDR_W-1:0]            b_load_addr,
    output wire signed [DATA_W-1:0]     b_load_data,

    output wire                         busy,
    output reg                          load_done
);

    localparam [1:0] ST_IDLE   = 2'd0;
    localparam [1:0] ST_LOAD_A = 2'd1;
    localparam [1:0] ST_LOAD_B = 2'd2;
    localparam [1:0] ST_DONE   = 2'd3;

    reg [1:0] state;

    reg [TILE_ROW_W-1:0]  saved_tile_row;
    reg [TILE_COL_W-1:0]  saved_tile_col;
    reg [K_BASE_W-1:0]    saved_k_base;
    reg [LEN_W-1:0]       saved_k_length;
    reg [TILE_SIZE_W-1:0] saved_valid_rows;
    reg [TILE_SIZE_W-1:0] saved_valid_cols;

    reg [BANK_W-1:0] a_bank_counter;
    reg [ADDR_W-1:0] a_k_counter;

    reg [BANK_W-1:0] b_bank_counter;
    reg [ADDR_W-1:0] b_k_counter;

    wire a_element_valid;
    wire b_element_valid;

    assign cmd_ready = (state == ST_IDLE);

    assign busy =
        (state == ST_LOAD_A) ||
        (state == ST_LOAD_B);

    assign a_load_write_enable = (state == ST_LOAD_A);
    assign b_load_write_enable = (state == ST_LOAD_B);

    assign a_load_bank = a_bank_counter;
    assign a_load_addr = a_k_counter;

    assign b_load_bank = b_bank_counter;
    assign b_load_addr = b_k_counter;

    // A bank = physical systolic-array row.
    assign a_element_valid =
        (a_bank_counter < saved_valid_rows) &&
        (a_k_counter < saved_k_length);

    // B bank = physical systolic-array column.
    assign b_element_valid =
        (b_bank_counter < saved_valid_cols) &&
        (b_k_counter < saved_k_length);

    // A matrix is stored row-major:
    // A[global_row][global_k].
    assign a_mem_addr =
        a_element_valid ?
        ((saved_tile_row * N + a_bank_counter) * K +
         saved_k_base + a_k_counter) :
        0;

    // B matrix is stored row-major:
    // B[global_k][global_column].
    assign b_mem_addr =
        b_element_valid ?
        ((saved_k_base + b_k_counter) * P +
         saved_tile_col * N + b_bank_counter) :
        0;

    // Invalid edge rows/columns and unused K locations receive zero.
    assign a_load_data =
        a_element_valid ? a_mem_data : {DATA_W{1'b0}};

    assign b_load_data =
        b_element_valid ? b_mem_data : {DATA_W{1'b0}};

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;

            saved_tile_row   <= 0;
            saved_tile_col   <= 0;
            saved_k_base     <= 0;
            saved_k_length   <= 0;
            saved_valid_rows <= 0;
            saved_valid_cols <= 0;

            a_bank_counter <= 0;
            a_k_counter    <= 0;
            b_bank_counter <= 0;
            b_k_counter    <= 0;

            load_done <= 1'b0;
        end
        else begin
            load_done <= 1'b0;

            case (state)

                ST_IDLE: begin
                    if (cmd_valid) begin
                        saved_tile_row   <= tile_row_index;
                        saved_tile_col   <= tile_col_index;
                        saved_k_base     <= k_base;
                        saved_k_length   <= k_length;
                        saved_valid_rows <= valid_rows;
                        saved_valid_cols <= valid_cols;

                        a_bank_counter <= 0;
                        a_k_counter    <= 0;

                        state <= ST_LOAD_A;
                    end
                end

                ST_LOAD_A: begin
                    if (a_k_counter == MAX_K - 1) begin
                        a_k_counter <= 0;

                        if (a_bank_counter == N - 1) begin
                            b_bank_counter <= 0;
                            b_k_counter    <= 0;
                            state <= ST_LOAD_B;
                        end
                        else begin
                            a_bank_counter <= a_bank_counter + 1'b1;
                        end
                    end
                    else begin
                        a_k_counter <= a_k_counter + 1'b1;
                    end
                end

                ST_LOAD_B: begin
                    if (b_k_counter == MAX_K - 1) begin
                        b_k_counter <= 0;

                        if (b_bank_counter == N - 1) begin
                            state <= ST_DONE;
                        end
                        else begin
                            b_bank_counter <= b_bank_counter + 1'b1;
                        end
                    end
                    else begin
                        b_k_counter <= b_k_counter + 1'b1;
                    end
                end

                ST_DONE: begin
                    load_done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule

