
`timescale 1ns/1ps

module tb_buffered_tile_engine;

    localparam integer N = 8;
    localparam integer MAX_K = 8;
    localparam integer K_LENGTH = 5;

    localparam integer DATA_W = 8;
    localparam integer ADDR_W = $clog2(MAX_K);
    localparam integer BANK_W = $clog2(N);
    localparam integer LEN_W = $clog2(MAX_K + 1);

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;
    reg [LEN_W-1:0] k_length = K_LENGTH;
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

    wire [N*N*32-1:0] c_flat;

    wire [4:0] debug_step_count;
    wire [1:0] debug_state;
    wire debug_array_ce;

    integer A [0:N-1][0:MAX_K-1];
    integer B [0:MAX_K-1][0:N-1];

    integer r, c, k;
    integer expected;
    integer actual;
    integer array_ce_count;

    buffered_tile_engine #(
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .rst(rst),

        .start(start),
        .k_length(k_length),
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

        .c_flat(c_flat),

        .debug_step_count(debug_step_count),
        .debug_state(debug_state),
        .debug_array_ce(debug_array_ce)
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

    // Count real compute edges entering the systolic array.
    always @(posedge clk) begin
        if (rst)
            array_ce_count = 0;
        else if (debug_array_ce)
            array_ce_count = array_ce_count + 1;
    end

    initial begin
        // A bank r stores the K values of A row r.
        for (r = 0; r < N; r = r + 1)
            for (k = 0; k < MAX_K; k = k + 1)
                A[r][k] = r - 2*k + 3;

        // B bank c stores the K values of B column c.
        for (k = 0; k < MAX_K; k = k + 1)
            for (c = 0; c < N; c = c + 1)
                B[k][c] = 2*c - k - 3;

        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 0;

        if (!load_ready)
            $fatal(1, "FAIL: engine was not ready for tile loading");

        // Load first K_LENGTH entries of each A row.
        for (r = 0; r < N; r = r + 1)
            for (k = 0; k < K_LENGTH; k = k + 1)
                load_a_value(r, k, A[r][k]);

        // Load first K_LENGTH entries of each B column.
        for (c = 0; c < N; c = c + 1)
            for (k = 0; k < K_LENGTH; k = k + 1)
                load_b_value(c, k, B[k][c]);

        // Stop loading and start one K=5 tile.
        @(negedge clk);
        a_load_write_enable = 0;
        b_load_write_enable = 0;
        start = 1;

        @(negedge clk);
        start = 0;

        // The controller asserts done after final buffered data reaches array.
        wait (done == 1'b1);
        #1;

        if (error)
            $fatal(1, "FAIL: controller reported an error");

        if (busy)
            $fatal(1, "FAIL: engine stayed busy after done");

        if (!load_ready)
            $fatal(1, "FAIL: engine did not return to load-ready state");

        // Check all 64 C values.
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                expected = 0;

                for (k = 0; k < K_LENGTH; k = k + 1)
                    expected = expected + A[r][k] * B[k][c];

                actual = $signed(c_flat[(r*N+c)*32 +: 32]);

                if (actual !== expected)
                    $fatal(1,
                        "FAIL C[%0d][%0d]: expected=%0d actual=%0d",
                        r, c, expected, actual);
            end
        end

        // K+2N-2 actual compute edges reach the array.
        if (array_ce_count != K_LENGTH + 2*N - 2)
            $fatal(1,
                "FAIL: expected %0d array CE edges, got %0d",
                K_LENGTH + 2*N - 2, array_ce_count);

        $display(
            "PASS: buffered engine produced %0d compute edges",
            array_ce_count
        );

        $display("ALL BUFFERED TILE ENGINE TESTS PASSED");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Buffered tile engine simulation timeout");
    end

endmodule

