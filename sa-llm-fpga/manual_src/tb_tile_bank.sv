
`timescale 1ns/1ps

module tb_tile_bank;

    localparam integer DEPTH = 8;
    localparam integer ADDR_W = $clog2(DEPTH);

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;

    reg write_enable = 0;
    reg [ADDR_W-1:0] write_addr = 0;
    reg signed [7:0] write_data = 0;

    reg read_enable = 0;
    reg [ADDR_W-1:0] read_addr = 0;
    wire signed [7:0] read_data;

    integer i;
    integer values [0:DEPTH-1];

    tile_bank #(
        .DATA_W(8),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),

        .write_enable(write_enable),
        .write_addr(write_addr),
        .write_data(write_data),

        .read_enable(read_enable),
        .read_addr(read_addr),
        .read_data(read_data)
    );

    task write_value(
        input integer address,
        input integer value
    );
        begin
            @(negedge clk);

            write_enable = 1;
            write_addr = address;
            write_data = value;

            read_enable = 0;

            @(posedge clk);
            #1;
        end
    endtask

    task read_and_check(
        input integer address,
        input integer expected
    );
        begin
            @(negedge clk);

            write_enable = 0;
            read_enable = 1;
            read_addr = address;

            @(posedge clk);
            #1;

            if (read_data !== expected)
                $fatal(1,
                    "FAIL address=%0d expected=%0d actual=%0d",
                    address, expected, read_data);

            $display("PASS bank[%0d] = %0d",
                     address, read_data);
        end
    endtask

    initial begin
        values[0] = 0;
        values[1] = 7;
        values[2] = -3;
        values[3] = 127;
        values[4] = -128;
        values[5] = 45;
        values[6] = -72;
        values[7] = 12;

        // Synchronous reset clears only read_data.
        @(posedge clk);
        #1;

        if (read_data !== 0)
            $fatal(1, "FAIL: reset did not clear read_data");

        $display("PASS: reset cleared read_data");

        @(negedge clk);
        rst = 0;

        // Load all eight memory locations.
        for (i = 0; i < DEPTH; i = i + 1)
            write_value(i, values[i]);

        // Read and verify every location.
        for (i = 0; i < DEPTH; i = i + 1)
            read_and_check(i, values[i]);

        // Disable reading. Previous output must hold.
        @(negedge clk);
        read_enable = 0;
        read_addr = 0;

        @(posedge clk);
        #1;

        if (read_data !== values[DEPTH-1])
            $fatal(1, "FAIL: read_data changed while read disabled");

        $display("PASS: read_data held while read disabled");
        $display("ALL TILE BANK TESTS PASSED");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "Tile bank simulation timeout");
    end

endmodule

