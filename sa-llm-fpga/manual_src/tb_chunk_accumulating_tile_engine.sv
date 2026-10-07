
`timescale 1ns/1ps

module tb_chunk_accumulating_tile_engine;

    localparam integer N = 2;
    localparam integer MAX_K = 4;
    localparam integer K_CHUNK = 2;

    localparam integer DATA_W = 8;
    localparam integer ADDR_W = $clog2(MAX_K);
    localparam integer BANK_W = $clog2(N);
    localparam integer LEN_W = $clog2(MAX_K + 1);

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg clear_output = 0;

    reg start = 0;
    reg [LEN_W-1:0] k_length = K_CHUNK;
    reg accumulate = 0;
    reg stall = 0;

    reg a_load_write_enable = 0;
    reg [BANK_W-1:0] a_load_bank = 0;
    reg [ADDR_W-1:0] a_load_addr = 0;
    reg signed [DATA_W-1:0] a_load_data = 0;

    reg b_load_write_enable = 0;
    reg [BANK_W-1:0] b_load_bank = 0;
    reg [ADDR_W-1:0] b_load_addr = 0;
    reg signed [DATA_W-1:0] b_load_data = 0;

    wire load_ready;
    wire busy;
    wire done;
    wire error;
    wire [N*N*32-1:0] c_tile;

    integer A [0:N-1][0:MAX_K-1];
    integer B [0:MAX_K-1][0:N-1];

    chunk_accumulating_tile_engine #(
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .rst(rst),

        .clear_output(clear_output),

        .start(start),
        .k_length(k_length),
        .accumulate(accumulate),
        .stall(stall),

        .a_load_write_enable(a_load_write_enable),
        .a_load_bank(a_load_bank),
        .a_load_addr(a_load_addr),
        .a_load_data(a_load_data),

        .b_load_write_enable(b_load_write_enable),
        .b_load_bank(b_load_bank),
        .b_load_addr(b_load_addr),
        .b_load_data(b_load_data),

        .load_ready(load_ready),
        .busy(busy),
        .done(done),
        .error(error),

        .c_tile(c_tile)
    );

    task load_a_value(
        input integer bank,
        input integer address,
        input integer value
    );
        begin
            @(negedge clk);

            a_load_write_enable = 1;
            a_load_bank = bank;
            a_load_addr = address;
            a_load_data = value;

            b_load_write_enable = 0;

            @(posedge clk);
            #1;
        end
    endtask

    task load_b_value(
        input integer bank,
        input integer address,
        input integer value
    );
        begin
            @(negedge clk);

            a_load_write_enable = 0;

            b_load_write_enable = 1;
            b_load_bank = bank;
            b_load_addr = address;
            b_load_data = value;

            @(posedge clk);
            #1;
        end
    endtask

    task load_chunk(
        input integer base_k
    );
        integer rr, cc, kk;
        begin
            if (!load_ready)
                $fatal(1, "FAIL: engine was not ready for loading");

            for (rr = 0; rr < N; rr = rr + 1)
                for (kk = 0; kk < K_CHUNK; kk = kk + 1)
                    load_a_value(rr, kk, A[rr][base_k + kk]);

            for (cc = 0; cc < N; cc = cc + 1)
                for (kk = 0; kk < K_CHUNK; kk = kk + 1)
                    load_b_value(cc, kk, B[base_k + kk][cc]);

            @(negedge clk);
            a_load_write_enable = 0;
            b_load_write_enable = 0;
        end
    endtask

    task run_chunk(
        input integer accumulate_mode
    );
        begin
            @(negedge clk);
            accumulate = accumulate_mode;
            start = 1;

            @(negedge clk);
            start = 0;

            wait (done == 1'b1);
            #1;

            if (error)
                $fatal(1, "FAIL: engine reported an error");
        end
    endtask

    task check_result(
        input integer k_limit
    );
        integer rr, cc, kk;
        integer value_expected;
        integer value_actual;
        begin
            for (rr = 0; rr < N; rr = rr + 1) begin
                for (cc = 0; cc < N; cc = cc + 1) begin
                    value_expected = 0;

                    for (kk = 0; kk < k_limit; kk = kk + 1)
                        value_expected =
                            value_expected + A[rr][kk] * B[kk][cc];

                    value_actual =
                        $signed(c_tile[(rr*N+cc)*32 +: 32]);

                    if (value_actual !== value_expected)
                        $fatal(1,
                            "FAIL C[%0d][%0d]: expected=%0d actual=%0d",
                            rr, cc, value_expected, value_actual);
                end
            end
        end
    endtask

    initial begin
        // A: 2 rows x 4 K values.
        A[0][0] = 1;   A[0][1] = 2;
        A[0][2] = 3;   A[0][3] = 4;

        A[1][0] = -1;  A[1][1] = 0;
        A[1][2] = 2;   A[1][3] = -3;

        // B: 4 K values x 2 columns.
        B[0][0] = 2;   B[0][1] = -1;
        B[1][0] = 1;   B[1][1] = 3;
        B[2][0] = -2;  B[2][1] = 4;
        B[3][0] = 5;   B[3][1] = 1;

        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 0;

        // Clear C before the first K chunk.
        @(negedge clk);
        clear_output = 1;

        @(posedge clk);
        #1;

        @(negedge clk);
        clear_output = 0;

        // First K chunk uses K indices 0 and 1.
        load_chunk(0);
        run_chunk(0);

        check_result(2);
        $display("PASS: first K=2 chunk stored");

        // Second K chunk uses K indices 2 and 3.
        load_chunk(2);
        run_chunk(1);

        check_result(4);
        $display("PASS: second K=2 chunk accumulated");

        $display("ALL CHUNK-ACCUMULATING TILE ENGINE TESTS PASSED");
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "Chunk accumulating tile engine simulation timeout");
    end

endmodule

