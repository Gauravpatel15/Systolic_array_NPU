
`timescale 1ns/1ps

module tb_systolic_array_4x4;

    localparam integer N = 4;
    localparam integer K = 4;

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

    integer A [0:N-1][0:K-1];
    integer B [0:K-1][0:N-1];
    integer expected [0:N-1][0:N-1];

    integer r, c, k, t;
    integer index_a, index_b;
    integer actual;

    reg [N*N*32-1:0] saved_results;

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

    initial begin

        // A contains values 1 through 16, row by row.
        for (r = 0; r < N; r = r + 1)
            for (k = 0; k < K; k = k + 1)
                A[r][k] = r*K + k + 1;

        // B has 2 on its diagonal and -1 elsewhere.
        for (k = 0; k < K; k = k + 1)
            for (c = 0; c < N; c = c + 1)
                if (k == c)
                    B[k][c] = 2;
                else
                    B[k][c] = -1;

        // Independent mathematical reference.
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                expected[r][c] = 0;

                for (k = 0; k < K; k = k + 1)
                    expected[r][c] =
                        expected[r][c] + A[r][k]*B[k][c];
            end
        end

        // Keep reset active for two rising edges.
        repeat (2) @(posedge clk);

        // t counts enabled compute steps, not stalled edges.
        for (t = 0; t < K + 2*N - 2; t = t + 1) begin

            @(negedge clk);
            rst = 0;
            ce = 1;

            a_left = 0;
            b_top = 0;
            a_valid_left = 0;
            b_valid_top = 0;

            // Delay A row r by r enabled cycles.
            for (r = 0; r < N; r = r + 1) begin
                index_a = t - r;

                if ((index_a >= 0) && (index_a < K)) begin
                    a_left[r*8 +: 8] = A[r][index_a];
                    a_valid_left[r] = 1;
                end
            end

            // Delay B column c by c enabled cycles.
            for (c = 0; c < N; c = c + 1) begin
                index_b = t - c;

                if ((index_b >= 0) && (index_b < K)) begin
                    b_top[c*8 +: 8] = B[index_b][c];
                    b_valid_top[c] = 1;
                end
            end

            // Insert one global stall before compute step 4.
            if (t == 4) begin
                ce = 0;
                saved_results = c_flat;

                @(posedge clk);
                #1;

                if (c_flat !== saved_results)
                    $fatal(1, "FAIL: accumulators changed during stall");

                $display("PASS: global stall held all accumulators");

                // Resume with exactly the same boundary inputs.
                @(negedge clk);
                ce = 1;
            end

            @(posedge clk);
            #1;
        end

        // Compare all 16 hardware results with the reference.
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin

                actual = $signed(c_flat[(r*N+c)*32 +: 32]);

                if (actual !== expected[r][c])
                    $fatal(1,
                        "FAIL C[%0d][%0d]: expected=%0d actual=%0d",
                        r, c, expected[r][c], actual);

                $display("PASS C[%0d][%0d] = %0d",
                         r, c, actual);
            end
        end

        // Remove boundary inputs and check result stability.
        saved_results = c_flat;

        @(negedge clk);
        a_left = 0;
        b_top = 0;
        a_valid_left = 0;
        b_valid_top = 0;

        repeat (2*N) begin
            @(posedge clk);
            #1;

            if (c_flat !== saved_results)
                $fatal(1, "FAIL: completed results changed");
        end

        $display("ALL PARAMETERIZED N=4 TESTS PASSED");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "4x4 simulation timeout");
    end

endmodule

