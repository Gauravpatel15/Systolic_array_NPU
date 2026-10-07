
`timescale 1ns/1ps

module tb_tiled_gemm;

    localparam integer N = 8;

    localparam integer M = 16;
    localparam integer K = 16;
    localparam integer P = 16;

    localparam integer K_TILE = 8;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg clear = 0;
    reg ce = 1;

    reg [N*8-1:0] a_left = 0;
    reg [N*8-1:0] b_top = 0;

    reg [N-1:0] a_valid_left = 0;
    reg [N-1:0] b_valid_top = 0;

    wire [N*N*32-1:0] c_flat;

    integer A [0:M-1][0:K-1];
    integer B [0:K-1][0:P-1];

    integer expected [0:M-1][0:P-1];
    integer assembled [0:M-1][0:P-1];

    integer i, j, k;
    integer row0, col0, k0;
    integer tile_count = 0;

    systolic_array #(
        .N(N)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .ce(ce),

        .a_left(a_left),
        .b_top(b_top),

        .a_valid_left(a_valid_left),
        .b_valid_top(b_valid_top),

        .c_flat(c_flat)
    );

    task run_tile(
        input integer start_row,
        input integer start_col,
        input integer start_k
    );
        integer r, c, q, t;
        integer index_a, index_b;
        integer partial_expected;
        integer partial_actual;

        begin
            // Clear the PE accumulators before each partial tile.
            @(negedge clk);

            rst = 0;
            clear = 1;
            ce = 1;

            a_left = 0;
            b_top = 0;
            a_valid_left = 0;
            b_valid_top = 0;

            @(posedge clk);
            #1;

            if (c_flat !== {N*N*32{1'b0}})
                $fatal(1, "FAIL: tile clear");

            // Feed and drain one N x N output tile.
            for (t = 0; t < K_TILE + 2*N - 2; t = t + 1) begin

                @(negedge clk);
                clear = 0;

                a_left = 0;
                b_top = 0;
                a_valid_left = 0;
                b_valid_top = 0;

                for (r = 0; r < N; r = r + 1) begin
                    index_a = t - r;

                    if ((index_a >= 0) &&
                        (index_a < K_TILE)) begin

                        a_left[r*8 +: 8] =
                            A[start_row+r][start_k+index_a];

                        a_valid_left[r] = 1;
                    end
                end

                for (c = 0; c < N; c = c + 1) begin
                    index_b = t - c;

                    if ((index_b >= 0) &&
                        (index_b < K_TILE)) begin

                        b_top[c*8 +: 8] =
                            B[start_k+index_b][start_col+c];

                        b_valid_top[c] = 1;
                    end
                end

                @(posedge clk);
                #1;
            end

            // Verify each partial result, then save/add it.
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin

                    partial_expected = 0;

                    for (q = 0; q < K_TILE; q = q + 1)
                        partial_expected = partial_expected
                            + A[start_row+r][start_k+q]
                            * B[start_k+q][start_col+c];

                    partial_actual =
                        $signed(c_flat[(r*N+c)*32 +: 32]);

                    if (partial_actual !== partial_expected)
                        $fatal(1,
                            "FAIL partial tile: row=%0d col=%0d k=%0d PE=(%0d,%0d)",
                            start_row, start_col, start_k, r, c);

                    assembled[start_row+r][start_col+c] =
                        assembled[start_row+r][start_col+c]
                        + partial_actual;
                end
            end

            tile_count = tile_count + 1;

            $display(
                "PASS tile %0d: row_start=%0d col_start=%0d k_start=%0d",
                tile_count, start_row, start_col, start_k
            );

            // Freeze the array between tile calls.
            @(negedge clk);
            ce = 0;
            a_valid_left = 0;
            b_valid_top = 0;
        end
    endtask

    initial begin

        // Small signed values: every input fits in INT8.
        for (i = 0; i < M; i = i + 1)
            for (k = 0; k < K; k = k + 1)
                A[i][k] = ((i + 2*k) % 9) - 4;

        for (k = 0; k < K; k = k + 1)
            for (j = 0; j < P; j = j + 1)
                B[k][j] = ((3*k + j) % 7) - 3;

        // Full-size mathematical reference.
        for (i = 0; i < M; i = i + 1) begin
            for (j = 0; j < P; j = j + 1) begin

                expected[i][j] = 0;
                assembled[i][j] = 0;

                for (k = 0; k < K; k = k + 1)
                    expected[i][j] = expected[i][j]
                        + A[i][k]*B[k][j];
            end
        end

        repeat (2) @(posedge clk);

        // Four output tiles, with two K chunks each.
        for (row0 = 0; row0 < M; row0 = row0 + N)
            for (col0 = 0; col0 < P; col0 = col0 + N)
                for (k0 = 0; k0 < K; k0 = k0 + K_TILE)
                    run_tile(row0, col0, k0);

        // Compare all 256 assembled output elements.
        for (i = 0; i < M; i = i + 1)
            for (j = 0; j < P; j = j + 1)
                if (assembled[i][j] !== expected[i][j])
                    $fatal(1,
                        "FAIL C[%0d][%0d]: expected=%0d actual=%0d",
                        i, j, expected[i][j], assembled[i][j]);

        if (tile_count != 8)
            $fatal(1, "FAIL: expected 8 tile calls");

        $display("PASS: all 256 output elements match reference");
        $display("ALL TILED 16x16 GEMM TESTS PASSED");
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "Tiled GEMM simulation timeout");
    end

endmodule

