
`timescale 1ns/1ps

module tb_tiled_gemm_system;

    localparam integer M = 3;
    localparam integer K = 5;
    localparam integer P = 3;

    localparam integer N = 2;
    localparam integer MAX_K = 4;
    localparam integer DATA_W = 8;

    localparam integer M_TILES = (M + N - 1) / N;
    localparam integer P_TILES = (P + N - 1) / N;

    localparam integer TILE_ROW_W = $clog2(M_TILES);
    localparam integer TILE_COL_W = $clog2(P_TILES);
    localparam integer K_BASE_W = $clog2(K + 1);
    localparam integer TILE_SIZE_W = $clog2(N + 1);

    localparam integer A_MEM_ADDR_W = $clog2(M*K);
    localparam integer B_MEM_ADDR_W = $clog2(K*P);

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;
    reg stall = 0;

    wire busy;
    wire done;
    wire error;

    wire [A_MEM_ADDR_W-1:0] a_mem_addr;
    wire signed [DATA_W-1:0] a_mem_data;

    wire [B_MEM_ADDR_W-1:0] b_mem_addr;
    wire signed [DATA_W-1:0] b_mem_data;

    wire result_valid;
    wire [TILE_ROW_W-1:0] result_tile_row;
    wire [TILE_COL_W-1:0] result_tile_col;
    wire [TILE_SIZE_W-1:0] result_valid_rows;
    wire [TILE_SIZE_W-1:0] result_valid_cols;
    wire [N*N*32-1:0] result_tile;

    reg signed [DATA_W-1:0] A_mem [0:M*K-1];
    reg signed [DATA_W-1:0] B_mem [0:K*P-1];

    reg signed [31:0] C_mem [0:M*P-1];

    integer r, c, k;
    integer write_r, write_c;
    integer expected;
    integer actual;
    integer written_tile_count;

    assign a_mem_data = A_mem[a_mem_addr];
    assign b_mem_data = B_mem[b_mem_addr];

    tiled_gemm_system #(
        .M(M),
        .K(K),
        .P(P),
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .rst(rst),

        .start(start),
        .stall(stall),

        .busy(busy),
        .done(done),
        .error(error),

        .a_mem_addr(a_mem_addr),
        .a_mem_data(a_mem_data),

        .b_mem_addr(b_mem_addr),
        .b_mem_data(b_mem_data),

        .result_valid(result_valid),
        .result_tile_row(result_tile_row),
        .result_tile_col(result_tile_col),
        .result_valid_rows(result_valid_rows),
        .result_valid_cols(result_valid_cols),
        .result_tile(result_tile)
    );

    // Result-memory writer.
    // It writes only real matrix elements, never padded elements.
    always @(posedge clk) begin
        if (rst) begin
            written_tile_count <= 0;
        end
        else if (result_valid) begin
            for (write_r = 0; write_r < N; write_r = write_r + 1) begin
                for (write_c = 0; write_c < N; write_c = write_c + 1) begin
                    if ((write_r < result_valid_rows) &&
                        (write_c < result_valid_cols)) begin

                        C_mem[
                            (result_tile_row*N + write_r)*P +
                            result_tile_col*N + write_c
                        ] <= $signed(
                            result_tile[
                                (write_r*N + write_c)*32 +: 32
                            ]
                        );
                    end
                end
            end

            written_tile_count <= written_tile_count + 1;

            $display(
                "PASS: wrote C tile (%0d,%0d), valid=(%0d,%0d)",
                result_tile_row,
                result_tile_col,
                result_valid_rows,
                result_valid_cols
            );
        end
    end

    initial begin
        // A[r][k] = r*3 - k + 1.
        for (r = 0; r < M; r = r + 1)
            for (k = 0; k < K; k = k + 1)
                A_mem[r*K + k] = r*3 - k + 1;

        // B[k][c] = 2*k - c - 2.
        for (k = 0; k < K; k = k + 1)
            for (c = 0; c < P; c = c + 1)
                B_mem[k*P + c] = 2*k - c - 2;

        // Clear software model of external C memory.
        for (r = 0; r < M; r = r + 1)
            for (c = 0; c < P; c = c + 1)
                C_mem[r*P + c] = 0;

        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 0;

        @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait (done == 1'b1);
        #1;

        if (error)
            $fatal(1, "FAIL: tiled GEMM system reported an error");

        if (written_tile_count != M_TILES * P_TILES)
            $fatal(1,
                "FAIL: expected %0d C tiles, wrote %0d",
                M_TILES * P_TILES,
                written_tile_count
            );

        // Verify every final C element against normal software GEMM.
        for (r = 0; r < M; r = r + 1) begin
            for (c = 0; c < P; c = c + 1) begin
                expected = 0;

                for (k = 0; k < K; k = k + 1)
                    expected =
                        expected + A_mem[r*K + k] * B_mem[k*P + c];

                actual = $signed(C_mem[r*P + c]);

                if (actual !== expected)
                    $fatal(1,
                        "FAIL C[%0d][%0d]: expected=%0d actual=%0d",
                        r, c, expected, actual);

                $display(
                    "PASS C[%0d][%0d] = %0d",
                    r, c, actual
                );
            end
        end

        $display("ALL END-TO-END TILED GEMM SYSTEM TESTS PASSED");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "End-to-end tiled GEMM system simulation timeout");
    end

endmodule

