
`timescale 1ns/1ps

module tb_tile_loader;

    localparam integer M = 3;
    localparam integer K = 5;
    localparam integer P = 3;

    localparam integer N = 2;
    localparam integer MAX_K = 4;
    localparam integer DATA_W = 8;

    localparam integer ADDR_W = $clog2(MAX_K);
    localparam integer BANK_W = $clog2(N);
    localparam integer A_MEM_ADDR_W = $clog2(M*K);
    localparam integer B_MEM_ADDR_W = $clog2(K*P);

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;

    reg cmd_valid = 0;
    wire cmd_ready;

    reg [0:0] tile_row_index = 1;
    reg [0:0] tile_col_index = 1;

    reg [2:0] k_base = 4;
    reg [2:0] k_length = 1;

    reg [1:0] valid_rows = 1;
    reg [1:0] valid_cols = 1;

    wire [A_MEM_ADDR_W-1:0] a_mem_addr;
    wire signed [DATA_W-1:0] a_mem_data;

    wire [B_MEM_ADDR_W-1:0] b_mem_addr;
    wire signed [DATA_W-1:0] b_mem_data;

    wire a_load_write_enable;
    wire [BANK_W-1:0] a_load_bank;
    wire [ADDR_W-1:0] a_load_addr;
    wire signed [DATA_W-1:0] a_load_data;

    wire b_load_write_enable;
    wire [BANK_W-1:0] b_load_bank;
    wire [ADDR_W-1:0] b_load_addr;
    wire signed [DATA_W-1:0] b_load_data;

    wire busy;
    wire load_done;

    reg signed [DATA_W-1:0] A_mem [0:M*K-1];
    reg signed [DATA_W-1:0] B_mem [0:K*P-1];

    reg [N-1:0] a_read_enable = 0;
    reg [N*ADDR_W-1:0] a_read_addr = 0;
    wire [N*DATA_W-1:0] a_read_data;

    reg [N-1:0] b_read_enable = 0;
    reg [N*ADDR_W-1:0] b_read_addr = 0;
    wire [N*DATA_W-1:0] b_read_data;

    integer r, c, k;

    assign a_mem_data = A_mem[a_mem_addr];
    assign b_mem_data = B_mem[b_mem_addr];

    tile_loader #(
        .M(M),
        .K(K),
        .P(P),
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) loader (
        .clk(clk),
        .rst(rst),

        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),

        .tile_row_index(tile_row_index),
        .tile_col_index(tile_col_index),
        .k_base(k_base),
        .k_length(k_length),
        .valid_rows(valid_rows),
        .valid_cols(valid_cols),

        .a_mem_addr(a_mem_addr),
        .a_mem_data(a_mem_data),

        .b_mem_addr(b_mem_addr),
        .b_mem_data(b_mem_data),

        .a_load_write_enable(a_load_write_enable),
        .a_load_bank(a_load_bank),
        .a_load_addr(a_load_addr),
        .a_load_data(a_load_data),

        .b_load_write_enable(b_load_write_enable),
        .b_load_bank(b_load_bank),
        .b_load_addr(b_load_addr),
        .b_load_data(b_load_data),

        .busy(busy),
        .load_done(load_done)
    );

    banked_tile_buffer #(
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) activation_buffer (
        .clk(clk),
        .rst(rst),

        .load_write_enable(a_load_write_enable),
        .load_bank(a_load_bank),
        .load_addr(a_load_addr),
        .load_data(a_load_data),

        .read_enable(a_read_enable),
        .read_addr(a_read_addr),
        .read_data(a_read_data)
    );

    banked_tile_buffer #(
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) weight_buffer (
        .clk(clk),
        .rst(rst),

        .load_write_enable(b_load_write_enable),
        .load_bank(b_load_bank),
        .load_addr(b_load_addr),
        .load_data(b_load_data),

        .read_enable(b_read_enable),
        .read_addr(b_read_addr),
        .read_data(b_read_data)
    );

    task check_loaded_buffers;
        integer address;
        integer bank;
        integer expected_a;
        integer expected_b;
        integer actual_a;
        integer actual_b;
        begin
            for (address = 0; address < MAX_K; address = address + 1) begin

                @(negedge clk);

                a_read_enable = {N{1'b1}};
                b_read_enable = {N{1'b1}};

                for (bank = 0; bank < N; bank = bank + 1) begin
                    a_read_addr[bank*ADDR_W +: ADDR_W] = address;
                    b_read_addr[bank*ADDR_W +: ADDR_W] = address;
                end

                @(posedge clk);
                #1;

                for (bank = 0; bank < N; bank = bank + 1) begin

                    if (((1*N + bank) < M) && (address < 1))
                        expected_a = A_mem[(1*N + bank)*K + 4 + address];
                    else
                        expected_a = 0;

                    if (((1*N + bank) < P) && (address < 1))
                        expected_b = B_mem[(4 + address)*P + 1*N + bank];
                    else
                        expected_b = 0;

                    actual_a =
                        $signed(a_read_data[bank*DATA_W +: DATA_W]);

                    actual_b =
                        $signed(b_read_data[bank*DATA_W +: DATA_W]);

                    if (actual_a !== expected_a)
                        $fatal(1,
                            "FAIL A bank=%0d addr=%0d expected=%0d actual=%0d",
                            bank, address, expected_a, actual_a);

                    if (actual_b !== expected_b)
                        $fatal(1,
                            "FAIL B bank=%0d addr=%0d expected=%0d actual=%0d",
                            bank, address, expected_b, actual_b);
                end
            end
        end
    endtask

    initial begin
        // A[r][k] = r*10 + k - 7.
        for (r = 0; r < M; r = r + 1)
            for (k = 0; k < K; k = k + 1)
                A_mem[r*K + k] = r*10 + k - 7;

        // B[k][c] = k*10 + c - 5.
        for (k = 0; k < K; k = k + 1)
            for (c = 0; c < P; c = c + 1)
                B_mem[k*P + c] = k*10 + c - 5;

        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 0;

        if (!cmd_ready)
            $fatal(1, "FAIL: loader was not command-ready");

        // Request edge tile:
        // row tile 1 -> only physical row 0 is real.
        // col tile 1 -> only physical column 0 is real.
        // K base 4, K length 1 -> only local K address 0 is real.
        @(negedge clk);
        cmd_valid = 1;

        @(posedge clk);
        #1;

        @(negedge clk);
        cmd_valid = 0;

        wait (load_done == 1'b1);
        #1;

        check_loaded_buffers();

        $display("PASS: edge-tile A and B data loaded correctly");
        $display("PASS: invalid rows, columns, and K entries were zero-padded");
        $display("ALL TILE LOADER TESTS PASSED");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "Tile loader simulation timeout");
    end

endmodule

