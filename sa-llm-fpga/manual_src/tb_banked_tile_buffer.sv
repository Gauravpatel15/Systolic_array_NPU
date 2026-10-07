
`timescale 1ns/1ps

module tb_banked_tile_buffer;

    localparam integer N = 8;
    localparam integer MAX_K = 8;
    localparam integer DATA_W = 8;
    localparam integer ADDR_W = $clog2(MAX_K);
    localparam integer BANK_W = $clog2(N);

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;

    reg load_write_enable = 0;
    reg [BANK_W-1:0] load_bank = 0;
    reg [ADDR_W-1:0] load_addr = 0;
    reg signed [DATA_W-1:0] load_data = 0;

    reg [N-1:0] read_enable = 0;
    reg [N*ADDR_W-1:0] read_addr = 0;

    wire [N*DATA_W-1:0] read_data;

    integer values [0:N-1][0:MAX_K-1];
    integer bank, k;
    integer expected;
    integer actual;

    banked_tile_buffer #(
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .rst(rst),

        .load_write_enable(load_write_enable),
        .load_bank(load_bank),
        .load_addr(load_addr),
        .load_data(load_data),

        .read_enable(read_enable),
        .read_addr(read_addr),

        .read_data(read_data)
    );

    task load_value(
        input integer bank_number,
        input integer address,
        input integer value
    );
        begin
            @(negedge clk);

            load_write_enable = 1;
            load_bank = bank_number;
            load_addr = address;
            load_data = value;

            @(posedge clk);
            #1;
        end
    endtask

    task read_all_banks_and_check(
        input integer address
    );
        begin
            @(negedge clk);

            load_write_enable = 0;
            read_enable = {N{1'b1}};

            for (bank = 0; bank < N; bank = bank + 1)
                read_addr[bank*ADDR_W +: ADDR_W] = address;

            @(posedge clk);
            #1;

            for (bank = 0; bank < N; bank = bank + 1) begin
                expected = values[bank][address];

                actual =
                    $signed(read_data[bank*DATA_W +: DATA_W]);

                if (actual !== expected)
                    $fatal(1,
                        "FAIL bank=%0d addr=%0d expected=%0d actual=%0d",
                        bank, address, expected, actual);

                $display(
                    "PASS bank=%0d addr=%0d value=%0d",
                    bank, address, actual
                );
            end
        end
    endtask

    initial begin
        // Each bank receives eight signed INT8 values.
        for (bank = 0; bank < N; bank = bank + 1)
            for (k = 0; k < MAX_K; k = k + 1)
                values[bank][k] = bank*10 + k - 40;

        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 0;

        // Load 64 values: eight values into each of eight banks.
        for (bank = 0; bank < N; bank = bank + 1)
            for (k = 0; k < MAX_K; k = k + 1)
                load_value(bank, k, values[bank][k]);

        // All eight banks read the same K address in parallel.
        read_all_banks_and_check(0);
        read_all_banks_and_check(3);
        read_all_banks_and_check(7);

        // No read request: outputs hold their last values.
        @(negedge clk);
        read_enable = 0;

        @(posedge clk);
        #1;

        for (bank = 0; bank < N; bank = bank + 1) begin
            expected = values[bank][7];

            actual =
                $signed(read_data[bank*DATA_W +: DATA_W]);

            if (actual !== expected)
                $fatal(1,
                    "FAIL held output bank=%0d expected=%0d actual=%0d",
                    bank, expected, actual);
        end

        $display("PASS: all bank outputs held while reads disabled");
        $display("ALL BANKED TILE BUFFER TESTS PASSED");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Banked tile buffer simulation timeout");
    end

endmodule

