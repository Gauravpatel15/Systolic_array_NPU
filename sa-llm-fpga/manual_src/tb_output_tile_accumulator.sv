
`timescale 1ns/1ps

module tb_output_tile_accumulator;

    localparam integer N = 2;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg clear = 0;
    reg write_enable = 0;
    reg accumulate = 0;

    reg  [N*N*32-1:0] tile_result = 0;
    wire [N*N*32-1:0] c_tile;

    output_tile_accumulator #(
        .N(N)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .write_enable(write_enable),
        .accumulate(accumulate),
        .tile_result(tile_result),
        .c_tile(c_tile)
    );

    task check_value(
        input integer index,
        input integer expected
    );
        integer actual;
        begin
            actual = $signed(c_tile[index*32 +: 32]);

            if (actual !== expected)
                $fatal(1,
                    "FAIL C[%0d]: expected=%0d actual=%0d",
                    index, expected, actual);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 0;

        // First K-tile result: [[5, -2], [10, 0]]
        @(negedge clk);
        tile_result[0*32 +: 32] = 32'sd5;
        tile_result[1*32 +: 32] = -32'sd2;
        tile_result[2*32 +: 32] = 32'sd10;
        tile_result[3*32 +: 32] = 32'sd0;

        accumulate = 0;
        write_enable = 1;

        @(posedge clk);
        #1;

        check_value(0, 5);
        check_value(1, -2);
        check_value(2, 10);
        check_value(3, 0);

        $display("PASS: first K tile stored");

        // Second K-tile result: [[3, 7], [-4, 1]]
        @(negedge clk);
        tile_result[0*32 +: 32] = 32'sd3;
        tile_result[1*32 +: 32] = 32'sd7;
        tile_result[2*32 +: 32] = -32'sd4;
        tile_result[3*32 +: 32] = 32'sd1;

        accumulate = 1;
        write_enable = 1;

        @(posedge clk);
        #1;

        // Expected final result: [[8, 5], [6, 1]]
        check_value(0, 8);
        check_value(1, 5);
        check_value(2, 6);
        check_value(3, 1);

        $display("PASS: second K tile accumulated");

        // Check output remains unchanged when writing is disabled.
        @(negedge clk);
        write_enable = 0;
        tile_result = 0;

        @(posedge clk);
        #1;

        check_value(0, 8);
        check_value(1, 5);
        check_value(2, 6);
        check_value(3, 1);

        // Clear before beginning the next output tile.
        @(negedge clk);
        clear = 1;

        @(posedge clk);
        #1;

        check_value(0, 0);
        check_value(1, 0);
        check_value(2, 0);
        check_value(3, 0);

        $display("PASS: output tile clear");
        $display("ALL OUTPUT TILE ACCUMULATOR TESTS PASSED");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "Output accumulator simulation timeout");
    end

endmodule

