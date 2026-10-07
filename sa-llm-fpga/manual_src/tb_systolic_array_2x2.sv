
`timescale 1ns/1ps

module tb_systolic_array;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg clear = 0;
    reg ce = 1;

    reg signed [7:0] a_row0 = 0;
    reg signed [7:0] a_row1 = 0;
    reg signed [7:0] b_col0 = 0;
    reg signed [7:0] b_col1 = 0;

    reg a_valid_row0 = 0;
    reg a_valid_row1 = 0;
    reg b_valid_col0 = 0;
    reg b_valid_col1 = 0;

    wire signed [31:0] c00;
    wire signed [31:0] c01;
    wire signed [31:0] c10;
    wire signed [31:0] c11;

        systolic_array #(
        .N(2)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .ce(ce),

        .a_left({a_row1, a_row0}),
        .b_top({b_col1, b_col0}),

        .a_valid_left({a_valid_row1, a_valid_row0}),
        .b_valid_top({b_valid_col1, b_valid_col0}),

        .c_flat({c11, c10, c01, c00})
    );

    task check_results(
        input integer e00,
        input integer e01,
        input integer e10,
        input integer e11
    );
        begin
            @(posedge clk);
            #1;

            if ((c00 !== e00) ||
                (c01 !== e01) ||
                (c10 !== e10) ||
                (c11 !== e11)) begin

                $display("Expected: [[%0d,%0d],[%0d,%0d]]",
                         e00, e01, e10, e11);

                $fatal(1, "Got: [[%0d,%0d],[%0d,%0d]]",
                       c00, c01, c10, c11);
            end

            $display("PASS: time=%0t C=[[%0d,%0d],[%0d,%0d]]",
                     $time, c00, c01, c10, c11);
        end
    endtask

    initial begin
        // First rising edge resets all four PEs.
        check_results(0, 0, 0, 0);

        // Compute edge 0: only row 0 and column 0 start.
        @(negedge clk);
        rst = 0;

        a_row0 = 1;
        a_row1 = 0;
        b_col0 = 5;
        b_col1 = 0;

        a_valid_row0 = 1;
        a_valid_row1 = 0;
        b_valid_col0 = 1;
        b_valid_col1 = 0;

        check_results(5, 0, 0, 0);

        // Compute edge 1: start row 1 and column 1.
        @(negedge clk);

        a_row0 = 2;
        a_row1 = 3;
        b_col0 = 7;
        b_col1 = 6;

        a_valid_row0 = 1;
        a_valid_row1 = 1;
        b_valid_col0 = 1;
        b_valid_col1 = 1;

        check_results(19, 6, 15, 0);

        // Compute edge 2: finish row 1 and column 1.
        @(negedge clk);

        a_row0 = 0;
        a_row1 = 4;
        b_col0 = 0;
        b_col1 = 8;

        a_valid_row0 = 0;
        a_valid_row1 = 1;
        b_valid_col0 = 0;
        b_valid_col1 = 1;

        check_results(19, 22, 43, 18);

        // Compute edge 3: no new operands; drain the array.
        @(negedge clk);

        a_row0 = 0;
        a_row1 = 0;
        b_col0 = 0;
        b_col1 = 0;

        a_valid_row0 = 0;
        a_valid_row1 = 0;
        b_valid_col0 = 0;
        b_valid_col1 = 0;

        check_results(19, 22, 43, 50);

        // One extra clock must not change the completed result.
        check_results(19, 22, 43, 50);
                // Clear the previous matrix result.
        // Clear must work even when ce = 0.
        @(negedge clk);
        clear = 1;
        ce = 0;

        check_results(0, 0, 0, 0);

        // Negative-matrix test: compute edge 0.
        @(negedge clk);
        clear = 0;
        ce = 1;

        a_row0 = 1;
        a_row1 = 0;
        b_col0 = -5;
        b_col1 = 0;

        a_valid_row0 = 1;
        a_valid_row1 = 0;
        b_valid_col0 = 1;
        b_valid_col1 = 0;

        check_results(-5, 0, 0, 0);

        // Present the next operands, but PAUSE the array.
        @(negedge clk);
        ce = 0;

        a_row0 = -2;
        a_row1 = -3;
        b_col0 = 7;
        b_col1 = 6;

        a_valid_row0 = 1;
        a_valid_row1 = 1;
        b_valid_col0 = 1;
        b_valid_col1 = 1;

        // No PE should update during this clock edge.
        check_results(-5, 0, 0, 0);

        // RESUME: keep the same operands and valid signals.
        @(negedge clk);
        ce = 1;

        check_results(-19, 6, 15, 0);

        // Compute edge 2.
        @(negedge clk);

        a_row0 = 0;
        a_row1 = 4;
        b_col0 = 0;
        b_col1 = -8;

        a_valid_row0 = 0;
        a_valid_row1 = 1;
        b_valid_col0 = 0;
        b_valid_col1 = 1;

        check_results(-19, 22, 43, -18);

        // Compute edge 3: drain the array.
        @(negedge clk);

        a_row0 = 0;
        a_row1 = 0;
        b_col0 = 0;
        b_col1 = 0;

        a_valid_row0 = 0;
        a_valid_row1 = 0;
        b_valid_col0 = 0;
        b_valid_col1 = 0;

        check_results(-19, 22, 43, -50);

        // Completed results must remain stable.
        check_results(-19, 22, 43, -50);

        $display("PASS: negative matrix and global stall");

        $display("ALL PARAMETERIZED N=2 TESTS PASSED");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "Array simulation timeout");
    end

endmodule

