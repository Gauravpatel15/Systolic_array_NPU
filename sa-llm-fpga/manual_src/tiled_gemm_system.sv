
`timescale 1ns/1ps

module tiled_gemm_system #(
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

    parameter integer LEN_W =
        $clog2(MAX_K + 1),

    parameter integer M_TILES =
        (M + N - 1) / N,

    parameter integer P_TILES =
        (P + N - 1) / N,

    parameter integer TILE_ROW_W =
        (M_TILES <= 1) ? 1 : $clog2(M_TILES),

    parameter integer TILE_COL_W =
        (P_TILES <= 1) ? 1 : $clog2(P_TILES),

    parameter integer K_BASE_W =
        (K <= 1) ? 1 : $clog2(K + 1),

    parameter integer TILE_SIZE_W =
        (N <= 1) ? 1 : $clog2(N + 1),

    parameter integer A_MEM_ADDR_W =
        ((M*K) <= 1) ? 1 : $clog2(M*K),

    parameter integer B_MEM_ADDR_W =
        ((K*P) <= 1) ? 1 : $clog2(K*P)
) (
    input  wire                         clk,
    input  wire                         rst,

    input  wire                         start,
    input  wire                         stall,

    output wire                         busy,
    output wire                         done,
    output wire                         error,

    // Read ports for full A and B matrix memory.
    output wire [A_MEM_ADDR_W-1:0]      a_mem_addr,
    input  wire signed [DATA_W-1:0]     a_mem_data,

    output wire [B_MEM_ADDR_W-1:0]      b_mem_addr,
    input  wire signed [DATA_W-1:0]     b_mem_data,

    // Result tile output. External memory stores only valid rows/columns.
    output wire                         result_valid,
    output wire [TILE_ROW_W-1:0]        result_tile_row,
    output wire [TILE_COL_W-1:0]        result_tile_col,
    output wire [TILE_SIZE_W-1:0]       result_valid_rows,
    output wire [TILE_SIZE_W-1:0]       result_valid_cols,
    output wire [N*N*32-1:0]            result_tile
);

    wire scheduler_busy;
    wire scheduler_done;
    wire scheduler_cmd_valid;
    wire loader_cmd_ready;

    wire [TILE_ROW_W-1:0] scheduler_tile_row;
    wire [TILE_COL_W-1:0] scheduler_tile_col;
    wire [K_BASE_W-1:0] scheduler_k_base;
    wire [LEN_W-1:0] scheduler_k_length;

    wire scheduler_accumulate;
    wire scheduler_first_k_chunk;
    wire scheduler_last_k_chunk;

    wire [TILE_SIZE_W-1:0] scheduler_valid_rows;
    wire [TILE_SIZE_W-1:0] scheduler_valid_cols;

    reg scheduler_chunk_done;

    wire a_load_write_enable;
    wire [BANK_W-1:0] a_load_bank;
    wire [ADDR_W-1:0] a_load_addr;
    wire signed [DATA_W-1:0] a_load_data;

    wire b_load_write_enable;
    wire [BANK_W-1:0] b_load_bank;
    wire [ADDR_W-1:0] b_load_addr;
    wire signed [DATA_W-1:0] b_load_data;

    wire loader_busy;
    wire loader_done;

    wire engine_load_ready;
    wire engine_busy;
    wire engine_done;
    wire engine_error;
    wire [N*N*32-1:0] engine_c_tile;

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_WAIT_LOAD   = 3'd1;
    localparam [2:0] ST_CLEAR_C     = 3'd2;
    localparam [2:0] ST_START_ENGINE = 3'd3;
    localparam [2:0] ST_WAIT_ENGINE = 3'd4;
    localparam [2:0] ST_WRITE_RESULT = 3'd5;

    reg [2:0] control_state;

    wire clear_output;
    wire engine_start;

    assign clear_output =
        (control_state == ST_CLEAR_C);

    assign engine_start =
        (control_state == ST_START_ENGINE);

    assign result_valid =
        (control_state == ST_WRITE_RESULT);

    assign result_tile_row = scheduler_tile_row;
    assign result_tile_col = scheduler_tile_col;
    assign result_valid_rows = scheduler_valid_rows;
    assign result_valid_cols = scheduler_valid_cols;
    assign result_tile = engine_c_tile;

    assign done = scheduler_done;
    assign error = engine_error;

    assign busy =
        scheduler_busy ||
        loader_busy ||
        engine_busy ||
        (control_state != ST_IDLE);

    gemm_tile_scheduler #(
        .M(M),
        .K(K),
        .P(P),
        .N(N),
        .MAX_K(MAX_K)
    ) scheduler (
        .clk(clk),
        .rst(rst),

        .start(start),
        .cmd_ready(loader_cmd_ready),
        .chunk_done(scheduler_chunk_done),

        .busy(scheduler_busy),
        .done(scheduler_done),

        .cmd_valid(scheduler_cmd_valid),

        .tile_row_index(scheduler_tile_row),
        .tile_col_index(scheduler_tile_col),

        .k_base(scheduler_k_base),
        .k_length(scheduler_k_length),

        .accumulate(scheduler_accumulate),
        .first_k_chunk(scheduler_first_k_chunk),
        .last_k_chunk(scheduler_last_k_chunk),

        .valid_rows(scheduler_valid_rows),
        .valid_cols(scheduler_valid_cols)
    );

    tile_loader #(
        .M(M),
        .K(K),
        .P(P),
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) loader (
        .clk(clk),
        .rst(rst),

        .cmd_valid(scheduler_cmd_valid),
        .cmd_ready(loader_cmd_ready),

        .tile_row_index(scheduler_tile_row),
        .tile_col_index(scheduler_tile_col),
        .k_base(scheduler_k_base),
        .k_length(scheduler_k_length),
        .valid_rows(scheduler_valid_rows),
        .valid_cols(scheduler_valid_cols),

        .a_mem_addr(a_mem_addr),
        .a_mem_data(a_mem_data),

        .b_mem_addr(b_mem_addr),
        .b_mem_data(b_mem_data),

        .a_load_write_enable(a_load_write_enable),
        .a_load_bank(a_load_bank),
        .a_load_addr(a_load_addr),
        .a_load_data(a_load_data),

        .b_load_write_enable(b_load_write_enable),
        .b_load_bank(b_load_bank),
        .b_load_addr(b_load_addr),
        .b_load_data(b_load_data),

        .busy(loader_busy),
        .load_done(loader_done)
    );

    chunk_accumulating_tile_engine #(
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) engine (
        .clk(clk),
        .rst(rst),

        .clear_output(clear_output),

        .start(engine_start),
        .k_length(scheduler_k_length),
        .accumulate(scheduler_accumulate),
        .stall(stall),

        .a_load_write_enable(a_load_write_enable),
        .a_load_bank(a_load_bank),
        .a_load_addr(a_load_addr),
        .a_load_data(a_load_data),

        .b_load_write_enable(b_load_write_enable),
        .b_load_bank(b_load_bank),
        .b_load_addr(b_load_addr),
        .b_load_data(b_load_data),

        .load_ready(engine_load_ready),
        .busy(engine_busy),
        .done(engine_done),
        .error(engine_error),

        .c_tile(engine_c_tile)
    );

    always @(posedge clk) begin
        if (rst) begin
            control_state <= ST_IDLE;
            scheduler_chunk_done <= 1'b0;
        end
        else begin
            scheduler_chunk_done <= 1'b0;

            case (control_state)

                ST_IDLE: begin
                    if (start)
                        control_state <= ST_WAIT_LOAD;
                end

                ST_WAIT_LOAD: begin
                    if (scheduler_done) begin
                        control_state <= ST_IDLE;
                    end
                    else if (loader_done) begin
                        if (scheduler_first_k_chunk)
                            control_state <= ST_CLEAR_C;
                        else
                            control_state <= ST_START_ENGINE;
                    end
                end

                ST_CLEAR_C: begin
                    control_state <= ST_START_ENGINE;
                end

                ST_START_ENGINE: begin
                    control_state <= ST_WAIT_ENGINE;
                end

                ST_WAIT_ENGINE: begin
                    if (engine_done) begin
                        if (scheduler_last_k_chunk) begin
                            control_state <= ST_WRITE_RESULT;
                        end
                        else begin
                            scheduler_chunk_done <= 1'b1;
                            control_state <= ST_WAIT_LOAD;
                        end
                    end
                end

                ST_WRITE_RESULT: begin
                    scheduler_chunk_done <= 1'b1;
                    control_state <= ST_WAIT_LOAD;
                end

                default: begin
                    control_state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule

