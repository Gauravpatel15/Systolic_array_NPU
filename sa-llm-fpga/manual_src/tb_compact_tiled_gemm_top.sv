
`timescale 1ns/1ps

module tb_compact_tiled_gemm_top;

    localparam integer M = 3;
    localparam integer K = 5;
    localparam integer P = 3;

    localparam integer N = 2;
    localparam integer MAX_K = 4;
    localparam integer DATA_W = 8;

    localparam integer A_MEM_ADDR_W = $clog2(M*K);
    localparam integer B_MEM_ADDR_W = $clog2(K*P);
    localparam integer C_MEM_ADDR_W = $clog2(M*P);

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;
    reg stall = 0;

    wire busy;
    wire done;
    wire error;

    wire [A_MEM_ADDR_W-1:0] a_mem_addr;
    wire signed [DATA_W-1:0] a_mem_data;

    wire [B_MEM_ADDR_W-1:0] b_mem_addr;
    wire signed [DATA_W-1:0] b_mem_data;

    wire c_write_enable;
    wire [C_MEM_ADDR_W-1:0] c_write_addr;
    wire signed [31:0] c_write_data;

    reg signed [DATA_W-1:0] A_mem [0:M*K-1];
    reg signed [DATA_W-1:0] B_mem [0:K*P-1];
    reg signed [31:0] C_mem [0:M*P-1];

    integer r, c, k;
    integer expected;
    integer actual;
    integer write_count;

    assign a_mem_data = A_mem[a_mem_addr];
    assign b_mem_data = B_mem[b_mem_addr];

    compact_tiled_gemm_top #(
        .M(M),
        .K(K),
        .P(P),
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .stall(stall),

        .busy(busy),
        .done(done),
        .error(error),

        .a_mem_addr(a_mem_addr),
        .a_mem_data(a_mem_data),

        .b_mem_addr(b_mem_addr),
        .b_mem_data(b_mem_data),

        .c_write_enable(c_write_enable),
        .c_write_addr(c_write_addr),
        .c_write_data(c_write_data)
    );

    // Model external C memory.
    always @(posedge clk) begin
        if (rst) begin
            write_count <= 0;
        end
        else if (c_write_enable) begin
            C_mem[c_write_addr] <= c_write_data;
            write_count <= write_count + 1;

            $display(
                "C memory write: addr=%0d data=%0d",
                c_write_addr,
                c_write_data
            );
        end
    end

    initial begin
        // A[r][k] = r*3 - k + 1.
        for (r = 0; r < M; r = r + 1)
            for (k = 0; k < K; k = k + 1)
                A_mem[r*K + k] = r*3 - k + 1;

        // B[k][c] = 2*k - c - 2.
        for (k = 0; k < K; k = k + 1)
            for (c = 0; c < P; c = c + 1)
                B_mem[k*P + c] = 2*k - c - 2;

        for (r = 0; r < M; r = r + 1)
            for (c = 0; c < P; c = c + 1)
                C_mem[r*P + c] = 0;

        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 0;

        @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait (done == 1'b1);
        #1;

        if (error)
            $fatal(1, "FAIL: compact top reported an error");

        if (write_count != M*P)
            $fatal(1,
                "FAIL: expected %0d C writes, got %0d",
                M*P,
                write_count
            );

        for (r = 0; r < M; r = r + 1) begin
            for (c = 0; c < P; c = c + 1) begin
                expected = 0;

                for (k = 0; k < K; k = k + 1)
                    expected =
                        expected + A_mem[r*K + k] * B_mem[k*P + c];

                actual = $signed(C_mem[r*P + c]);

                if (actual !== expected)
                    $fatal(1,
                        "FAIL C[%0d][%0d]: expected=%0d actual=%0d",
                        r, c, expected, actual);

                $display(
                    "PASS C[%0d][%0d] = %0d",
                    r, c, actual
                );
            end
        end

        $display("ALL COMPACT TOP TESTS PASSED");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "Compact top simulation timeout");
    end

endmodule

