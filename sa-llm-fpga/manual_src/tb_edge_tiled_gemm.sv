
`timescale 1ns/1ps

module tb_edge_tiled_gemm;

    localparam integer N = 8;

    localparam integer M = 11;
    localparam integer K = 13;
    localparam integer P = 10;

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
    integer k_length;
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
        input integer start_k,
        input integer length_k
    );

        integer r, c, q, t;
        integer index_a, index_b;
        integer partial_expected;
        integer partial_actual;

        begin
            // Clear the array before one partial K tile.
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
                $fatal(1, "FAIL: PE accumulators did not clear");

            // Feed values and drain the systolic pipeline.
            for (t = 0; t < length_k + 2*N - 2; t = t + 1) begin

                @(negedge clk);

                clear = 0;
                a_left = 0;
                b_top = 0;
                a_valid_left = 0;
                b_valid_top = 0;

                // Send only real A rows and real K values.
                for (r = 0; r < N; r = r + 1) begin
                    index_a = t - r;

                    if ((start_row + r < M) &&
                        (index_a >= 0) &&
                        (index_a < length_k)) begin

                        a_left[r*8 +: 8] =
                            A[start_row+r][start_k+index_a];

                        a_valid_left[r] = 1;
                    end
                end

                // Send only real B columns and real K values.
                for (c = 0; c < N; c = c + 1) begin
                    index_b = t - c;

                    if ((start_col + c < P) &&
                        (index_b >= 0) &&
                        (index_b < length_k)) begin

                        b_top[c*8 +: 8] =
                            B[start_k+index_b][start_col+c];

                        b_valid_top[c] = 1;
                    end
                end

                @(posedge clk);
                #1;
            end

            // Check only outputs that belong to the actual M x P matrix.
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin

                    if ((start_row + r < M) &&
                        (start_col + c < P)) begin

                        partial_expected = 0;

                        for (q = 0; q < length_k; q = q + 1)
                            partial_expected = partial_expected
                                + A[start_row+r][start_k+q]
                                * B[start_k+q][start_col+c];

                        partial_actual =
                            $signed(c_flat[(r*N+c)*32 +: 32]);

                        if (partial_actual !== partial_expected)
                            $fatal(1,
                                "FAIL tile row=%0d col=%0d k=%0d PE=(%0d,%0d): expected=%0d actual=%0d",
                                start_row, start_col, start_k,
                                r, c, partial_expected, partial_actual);

                        assembled[start_row+r][start_col+c] =
                            assembled[start_row+r][start_col+c]
                            + partial_actual;
                    end
                end
            end

            tile_count = tile_count + 1;

            $display(
                "PASS tile %0d: row_start=%0d col_start=%0d k_start=%0d k_length=%0d",
                tile_count, start_row, start_col, start_k, length_k
            );

            // Stop state changes between tile calls.
            @(negedge clk);
            ce = 0;
            a_valid_left = 0;
            b_valid_top = 0;
        end
    endtask

    initial begin

        // Every element stays safely inside signed INT8 range.
        for (i = 0; i < M; i = i + 1)
            for (k = 0; k < K; k = k + 1)
                A[i][k] = ((3*i + 2*k) % 9) - 4;

        for (k = 0; k < K; k = k + 1)
            for (j = 0; j < P; j = j + 1)
                B[k][j] = ((5*k + j) % 7) - 3;

        // Reference matrix multiplication in the testbench.
        for (i = 0; i < M; i = i + 1) begin
            for (j = 0; j < P; j = j + 1) begin
                expected[i][j] = 0;
                assembled[i][j] = 0;

                for (k = 0; k < K; k = k + 1)
                    expected[i][j] = expected[i][j]
                        + A[i][k] * B[k][j];
            end
        end

        repeat (2) @(posedge clk);

        // Process all edge tiles and both K chunks.
        for (row0 = 0; row0 < M; row0 = row0 + N) begin
            for (col0 = 0; col0 < P; col0 = col0 + N) begin
                for (k0 = 0; k0 < K; k0 = k0 + K_TILE) begin

                    if (K - k0 < K_TILE)
                        k_length = K - k0;
                    else
                        k_length = K_TILE;

                    run_tile(row0, col0, k0, k_length);
                end
            end
        end

        // Compare all 110 final outputs.
        for (i = 0; i < M; i = i + 1) begin
            for (j = 0; j < P; j = j + 1) begin

                if (assembled[i][j] !== expected[i][j])
                    $fatal(1,
                        "FAIL C[%0d][%0d]: expected=%0d actual=%0d",
                        i, j, expected[i][j], assembled[i][j]);
            end
        end

        if (tile_count != 8)
            $fatal(1, "FAIL: expected 8 tile runs, got %0d", tile_count);

        $display("PASS: all 110 edge-tiled outputs match reference");
        $display("ALL EDGE-TILED 11x13 x 13x10 GEMM TESTS PASSED");
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "Edge-tiled GEMM simulation timeout");
    end

endmodule

