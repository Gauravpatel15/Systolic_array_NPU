
`timescale 1ns/1ps

module tb_mac_pe;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg clear = 0;
    reg ce = 1;

    reg signed [7:0] a_in = 0;
    reg signed [7:0] b_in = 0;

    reg a_valid_in = 0;
    reg b_valid_in = 0;

    wire signed [7:0] a_out;
    wire signed [7:0] b_out;
    wire a_valid_out;
    wire b_valid_out;
    wire signed [31:0] acc;

    mac_pe dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .ce(ce),
        .a_in(a_in),
        .b_in(b_in),
        .a_valid_in(a_valid_in),
        .b_valid_in(b_valid_in),
        .a_out(a_out),
        .b_out(b_out),
        .a_valid_out(a_valid_out),
        .b_valid_out(b_valid_out),
        .acc(acc)
    );

    task check_acc(input integer expected);
        begin
            @(posedge clk);
            #1;

            if (acc !== expected)
                $fatal(1, "FAIL: expected %0d, got %0d",
                       expected, acc);

            $display("PASS: time=%0t acc=%0d", $time, acc);
        end
    endtask

    initial begin
        check_acc(0);

        @(negedge clk);
        rst = 0;
        a_in = 3;
        b_in = 4;
        a_valid_in = 1;
        b_valid_in = 1;
        check_acc(12);

        @(negedge clk);
        a_in = -2;
        b_in = 5;
        check_acc(2);

        @(negedge clk);
        ce = 0;
        a_in = 10;
        b_in = 10;
        check_acc(2);

        @(negedge clk);
        ce = 1;
        b_valid_in = 0;
        check_acc(2);

        @(negedge clk);
        clear = 1;
        check_acc(0);
                // Test: minimum INT8 multiplied by minimum INT8
        @(negedge clk);
        clear = 0;
        ce = 1;
        a_valid_in = 1;
        b_valid_in = 1;
        a_in = -128;
        b_in = -128;
        check_acc(16384);

        // Check that operands and valid bits were forwarded
        if ((a_out !== 8'h80) ||
            (b_out !== 8'h80) ||
            (a_valid_out !== 1'b1) ||
            (b_valid_out !== 1'b1))
            $fatal(1, "FAIL: operand forwarding");

        $display("PASS: operand forwarding");

        // Add a negative product
        @(negedge clk);
        a_in = -128;
        b_in = 127;
        check_acc(128);

        // Multiplication by zero must not change the sum
        @(negedge clk);
        a_in = 0;
        b_in = 127;
        check_acc(128);

        $display("ALL PE TESTS PASSED");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "Simulation timeout");
    end

endmodule

