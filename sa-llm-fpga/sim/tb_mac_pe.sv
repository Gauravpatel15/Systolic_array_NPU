`timescale 1ns/1ps
module tb_mac_pe;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, clear=0, ce=1, av=0, bv=0;
    reg signed [7:0] a=0, b=0;
    wire signed [7:0] ao, bo;
    wire avo, bvo;
    wire signed [31:0] acc;
    wire signed [15:0] acc16;
    integer expected=0, steps=0, i, j;
    reg signed [15:0] expected16=0;
    reg signed [7:0] expected_a=0, expected_b=0;
    reg expected_av=0, expected_bv=0;
    mac_pe dut(.clk(clk), .rst(rst), .clear(clear), .ce(ce),
        .a_in(a), .b_in(b), .a_valid_in(av), .b_valid_in(bv),
        .a_out(ao), .b_out(bo), .a_valid_out(avo), .b_valid_out(bvo), .acc(acc));
    // Small accumulator makes deliberate overflow fast to exercise.
    mac_pe #(.ACC_W(16)) narrow(.clk(clk), .rst(rst), .clear(clear), .ce(ce),
        .a_in(a), .b_in(b), .a_valid_in(av), .b_valid_in(bv),
        .a_out(), .b_out(), .a_valid_out(), .b_valid_out(), .acc(acc16));

    task step(input integer ai, bi, input bit va, vb, enable, clr, reset);
        begin
            @(negedge clk);
            a=ai; b=bi; av=va; bv=vb; ce=enable; clear=clr; rst=reset;
            if (reset || clr) begin
                expected=0; expected16=0; expected_a=0; expected_b=0;
                expected_av=0; expected_bv=0;
            end else if (enable) begin
                expected_a=ai; expected_b=bi; expected_av=va; expected_bv=vb;
                if (va && vb) begin
                    expected=expected+ai*bi;
                    expected16=expected16+ai*bi;
                end
            end
            @(posedge clk); #1;
            if (acc !== expected || acc16 !== expected16 ||
                ao !== expected_a || bo !== expected_b ||
                avo !== expected_av || bvo !== expected_bv)
                $fatal(1, "PE mismatch step=%0d got=%0d expected=%0d", steps, acc, expected);
            steps=steps+1;
        end
    endtask

    initial begin
        step(0,0,0,0,1,0,1);
        step(3,4,1,1,1,0,0);      // 12
        step(-2,5,1,1,1,0,0);     // 2
        step(-128,-128,1,1,0,0,0);// stall, stays 2
        step(7,9,1,0,1,0,0);      // invalid pair, stays 2
        step(7,9,0,1,1,0,0);
        step(0,0,0,0,0,1,0);      // clear must work even while stalled
        repeat (5) step(-128,-128,1,1,1,0,0);
        step(0,0,0,0,0,0,1);      // reset while stalled
        // Exhaustively verify all 65,536 signed INT8 products in isolation.
        for (i=-128; i<=127; i=i+1)
            for (j=-128; j<=127; j=j+1) begin
                step(0,0,0,0,1,1,0);
                step(i,j,1,1,1,0,0);
            end
        $display("PASS tb_mac_pe: exhaustive INT8 products, accumulation, valid, stalls, reset, wrap (%0d steps)", steps);
        $finish;
    end
    initial begin #5000000; $fatal(1,"PE watchdog timeout"); end
endmodule
