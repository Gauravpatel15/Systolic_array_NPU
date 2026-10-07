
`timescale 1ns/1ps

module tb_tile_controller;

    localparam integer N = 8;
    localparam integer MAX_K = 8;
    localparam integer K_LENGTH = 5;
    localparam integer LEN_W = $clog2(MAX_K + 1);

    localparam [1:0] ST_FEED = 2'd2;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;
    reg [LEN_W-1:0] k_length = K_LENGTH;
    reg stall = 0;

    wire busy;
    wire done;
    wire error;

    wire array_clear;
    wire array_ce;

    wire [N-1:0] a_valid_left;
    wire [N-1:0] b_valid_top;

    wire [N*LEN_W-1:0] a_k_index;
    wire [N*LEN_W-1:0] b_k_index;

    wire [4:0] step_count;
    wire [1:0] state;

    reg [N*8-1:0] a_left;
    reg [N*8-1:0] b_top;

    wire [N*N*32-1:0] c_flat;

    integer A [0:N-1][0:MAX_K-1];
    integer B [0:MAX_K-1][0:N-1];

    integer r, c, k;
    integer expected;
    integer actual;
    integer ce_edge_count;

    reg [N*N*32-1:0] saved_results;

    tile_controller #(
        .N(N),
        .MAX_K(MAX_K)
    ) controller (
        .clk(clk),
        .rst(rst),

        .start(start),
        .k_length(k_length),
        .stall(stall),

        .busy(busy),
        .done(done),
        .error(error),

        .array_clear(array_clear),
        .array_ce(array_ce),

        .a_valid_left(a_valid_left),
        .b_valid_top(b_valid_top),

        .a_k_index(a_k_index),
        .b_k_index(b_k_index),

        .step_count(step_count),
        .state(state)
    );

    systolic_array #(
        .N(N)
    ) array (
        .clk(clk),
        .rst(rst),
        .clear(array_clear),
        .ce(array_ce),

        .a_left(a_left),
        .b_top(b_top),

        .a_valid_left(a_valid_left),
        .b_valid_top(b_valid_top),

        .c_flat(c_flat)
    );

    // Temporary testbench-only data source.
    // Future BRAM buffers will replace this block.
    always @* begin
        a_left = 0;
        b_top = 0;

        for (r = 0; r < N; r = r + 1) begin
            if (a_valid_left[r])
                a_left[r*8 +: 8] =
                    A[r][a_k_index[r*LEN_W +: LEN_W]];
        end

        for (c = 0; c < N; c = c + 1) begin
            if (b_valid_top[c])
                b_top[c*8 +: 8] =
                    B[b_k_index[c*LEN_W +: LEN_W]][c];
        end
    end

    // Count only enabled array clock edges.
    always @(posedge clk) begin
        if (rst)
            ce_edge_count = 0;
        else if (array_ce)
            ce_edge_count = ce_edge_count + 1;
    end

    initial begin
        // Small signed values, all valid INT8 values.
        for (r = 0; r < N; r = r + 1)
            for (k = 0; k < MAX_K; k = k + 1)
                A[r][k] = r - 2*k + 3;

        for (k = 0; k < MAX_K; k = k + 1)
            for (c = 0; c < N; c = c + 1)
                B[k][c] = 2*c - k - 3;

        repeat (2) @(posedge clk);

        // Start one K=5 tile.
        @(negedge clk);
        rst = 0;
        start = 1;

        @(negedge clk);
        start = 0;

        // Pause controller at feed step 3.
        wait ((state == ST_FEED) && (step_count == 3));

        @(negedge clk);
        stall = 1;
        saved_results = c_flat;

        @(posedge clk);
        #1;

        if (c_flat !== saved_results)
            $fatal(1, "FAIL: array changed during controller stall");

        $display("PASS: controller stall held array state");

        @(negedge clk);
        stall = 0;

        // done arrives after the final feed/drain edge.
        wait (done == 1'b1);
        #1;

        if (error)
            $fatal(1, "FAIL: controller raised error");

        if (busy)
            $fatal(1, "FAIL: controller stayed busy after done");

        // Compare all 64 results against normal dot products.
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin

                expected = 0;

                for (k = 0; k < K_LENGTH; k = k + 1)
                    expected = expected + A[r][k]*B[k][c];

                actual = $signed(c_flat[(r*N+c)*32 +: 32]);

                if (actual !== expected)
                    $fatal(1,
                        "FAIL C[%0d][%0d]: expected=%0d actual=%0d",
                        r, c, expected, actual);
            end
        end

        // One clear edge plus K+2N-2 feed/drain edges.
        if (ce_edge_count != 1 + K_LENGTH + 2*N - 2)
            $fatal(1,
                "FAIL: enabled edges expected=%0d actual=%0d",
                1 + K_LENGTH + 2*N - 2, ce_edge_count);

        $display("PASS: controller generated %0d enabled array edges",
                 ce_edge_count);

        $display("ALL TILE CONTROLLER TESTS PASSED");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "Tile controller simulation timeout");
    end

endmodule

