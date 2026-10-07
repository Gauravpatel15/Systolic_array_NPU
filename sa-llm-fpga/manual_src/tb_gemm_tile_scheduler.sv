
`timescale 1ns/1ps

module tb_gemm_tile_scheduler;

    localparam integer M = 11;
    localparam integer K = 13;
    localparam integer P = 10;

    localparam integer N = 8;
    localparam integer MAX_K = 8;

    localparam integer M_TILES = (M + N - 1) / N;
    localparam integer P_TILES = (P + N - 1) / N;
    localparam integer K_CHUNKS = (K + MAX_K - 1) / MAX_K;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;
    reg cmd_ready = 1;

    reg chunk_done = 0;
    reg pending_done = 0;

    wire busy;
    wire done;
    wire cmd_valid;

    wire [0:0] tile_row_index;
    wire [0:0] tile_col_index;
    wire [3:0] k_base;
    wire [3:0] k_length;

    wire accumulate;
    wire first_k_chunk;
    wire last_k_chunk;

    wire [3:0] valid_rows;
    wire [3:0] valid_cols;

    integer command_count;
    integer expected_row;
    integer expected_col;
    integer expected_k_base;
    integer expected_k_length;
    integer expected_rows;
    integer expected_cols;

    gemm_tile_scheduler #(
        .M(M),
        .K(K),
        .P(P),
        .N(N),
        .MAX_K(MAX_K)
    ) dut (
        .clk(clk),
        .rst(rst),

        .start(start),
        .cmd_ready(cmd_ready),
        .chunk_done(chunk_done),

        .busy(busy),
        .done(done),

        .cmd_valid(cmd_valid),

        .tile_row_index(tile_row_index),
        .tile_col_index(tile_col_index),

        .k_base(k_base),
        .k_length(k_length),

        .accumulate(accumulate),
        .first_k_chunk(first_k_chunk),
        .last_k_chunk(last_k_chunk),

        .valid_rows(valid_rows),
        .valid_cols(valid_cols)
    );

    always @(posedge clk) begin
        chunk_done <= 0;

        if (cmd_valid && cmd_ready) begin
            pending_done <= 1;
        end
        else if (pending_done) begin
            chunk_done <= 1;
            pending_done <= 0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            command_count = 0;
        end
        else if (cmd_valid && cmd_ready) begin

            expected_row =
                command_count / (P_TILES * K_CHUNKS);

            expected_col =
                (command_count / K_CHUNKS) % P_TILES;

            expected_k_base =
                (command_count % K_CHUNKS) * MAX_K;

            if (expected_k_base + MAX_K <= K)
                expected_k_length = MAX_K;
            else
                expected_k_length = K - expected_k_base;

            if (expected_row * N + N <= M)
                expected_rows = N;
            else
                expected_rows = M - expected_row * N;

            if (expected_col * N + N <= P)
                expected_cols = N;
            else
                expected_cols = P - expected_col * N;

            if (tile_row_index !== expected_row)
                $fatal(1, "FAIL: wrong tile row");

            if (tile_col_index !== expected_col)
                $fatal(1, "FAIL: wrong tile column");

            if (k_base !== expected_k_base)
                $fatal(1, "FAIL: wrong K base");

            if (k_length !== expected_k_length)
                $fatal(1, "FAIL: wrong K length");

            if (valid_rows !== expected_rows)
                $fatal(1, "FAIL: wrong valid row count");

            if (valid_cols !== expected_cols)
                $fatal(1, "FAIL: wrong valid column count");

            if (accumulate !== (expected_k_base != 0))
                $fatal(1, "FAIL: wrong accumulate flag");

            $display(
                "PASS command %0d: tile=(%0d,%0d), K=(%0d,%0d), valid=(%0d,%0d), accumulate=%0d",
                command_count,
                tile_row_index,
                tile_col_index,
                k_base,
                k_length,
                valid_rows,
                valid_cols,
                accumulate
            );

            command_count = command_count + 1;
        end
    end

    initial begin
        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 0;

        @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait (done == 1'b1);
        #1;

        if (command_count != M_TILES * P_TILES * K_CHUNKS)
            $fatal(1,
                "FAIL: expected %0d commands, got %0d",
                M_TILES * P_TILES * K_CHUNKS,
                command_count
            );

        $display("ALL GEMM TILE SCHEDULER TESTS PASSED");
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "GEMM tile scheduler simulation timeout");
    end

endmodule

