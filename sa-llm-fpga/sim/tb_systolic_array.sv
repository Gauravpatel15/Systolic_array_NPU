`timescale 1ns/1ps
// The testbench is the temporary scheduler. It is NOT a synthesizable controller.
module array_checker #(parameter integer N=2)(output reg finished=0);
    localparam M=11, K=17, P=13, K_TILE=5;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, clear=0, ce=1;
    reg [N*8-1:0] a_left=0, b_top=0;
    reg [N-1:0] av=0, bv=0;
    wire [N*N*32-1:0] results;
    reg signed [7:0] a_mem[0:M*K-1], b_mem[0:K*P-1];
    reg signed [31:0] golden[0:M*P-1];
    integer host_c[0:M*P-1];
    integer tile_a[0:N-1][0:K_TILE-1];
    integer tile_b[0:K_TILE-1][0:N-1];
    integer i,j,k,ti,tj,tk,klen,expected,got,passes=0;
    reg [N*N*32-1:0] held;
    systolic_array #(.N(N)) dut(.clk(clk), .rst(rst), .clear(clear), .ce(ce),
        .a_left(a_left), .b_top(b_top), .a_valid_left(av), .b_valid_top(bv), .c_flat(results));

    task run_tile(input integer depth, input bit stalls);
        integer t,r,c,idx,ref_value;
        begin
            @(negedge clk); rst=0; clear=1; ce=0; av=0; bv=0;
            @(posedge clk); #1;
            if (results !== {N*N*32{1'b0}}) $fatal(1,"N=%0d clear failed", N);
            // t counts enabled computation edges; first product is consumed at t=0.
            for (t=0; t<depth+2*N-2; t=t+1) begin
                @(negedge clk); clear=0; ce=1; a_left=0; b_top=0; av=0; bv=0;
                for (r=0; r<N; r=r+1) begin
                    idx=t-r;
                    if (idx>=0 && idx<depth) begin
                        a_left[r*8 +: 8]=tile_a[r][idx]; av[r]=1;
                    end
                end
                for (c=0; c<N; c=c+1) begin
                    idx=t-c;
                    if (idx>=0 && idx<depth) begin
                        b_top[c*8 +: 8]=tile_b[idx][c]; bv[c]=1;
                    end
                end
                if (stalls && t%3==1) begin
                    ce=0; held=results;
                    @(posedge clk); #1;
                    if (results !== held) $fatal(1,"N=%0d changed during stall",N);
                    @(negedge clk); ce=1; // keep boundary data stable; do not advance t
                end
                @(posedge clk); #1;
            end
            for (r=0; r<N; r=r+1)
                for (c=0; c<N; c=c+1) begin
                    ref_value=0;
                    for (idx=0; idx<depth; idx=idx+1)
                        ref_value=ref_value+tile_a[r][idx]*tile_b[idx][c];
                    if ($signed(results[(r*N+c)*32 +: 32]) !== ref_value)
                        $fatal(1,"N=%0d PE[%0d,%0d] got=%0d expected=%0d",N,r,c,
                            $signed(results[(r*N+c)*32 +: 32]),ref_value);
                end
            @(negedge clk); av=0; bv=0; a_left=0; b_top=0;
            held=results;
            // Drain invalid tokens and prove results remain stable.
            repeat (2*N+1) begin
                @(posedge clk); #1;
                if (results !== held) $fatal(1,"N=%0d extra accumulation after drain",N);
            end
            passes=passes+1;
        end
    endtask

    initial begin
        // Memory files are copied into the simulator directory by the Tcl scripts.
        $readmemh("a.mem",a_mem); $readmemh("b.mem",b_mem); $readmemh("c.mem",golden);
        for (i=0;i<M*K;i=i+1) if ((^a_mem[i]) === 1'bx) $fatal(1,"Missing A vectors");
        for (i=0;i<K*P;i=i+1) if ((^b_mem[i]) === 1'bx) $fatal(1,"Missing B vectors");
        for (i=0;i<M*P;i=i+1) if ((^golden[i]) === 1'bx) $fatal(1,"Missing C vectors");
        repeat (2) @(posedge clk);
        for (i=0;i<N;i=i+1)
            for (k=0;k<K_TILE;k=k+1) begin
                tile_a[i][k]=0; tile_b[k][i]=0;
            end
        run_tile(1,0); // zero matrix, minimal K
        tile_a[0][0]=1; tile_a[0][1]=2;
        tile_a[1][0]=3; tile_a[1][1]=4;
        tile_b[0][0]=5; tile_b[0][1]=6;
        tile_b[1][0]=7; tile_b[1][1]=8;
        run_tile(2,0); // top-left result [[19,22],[43,50]]
        if ($signed(results[0 +: 32]) !== 19 ||
            $signed(results[32 +: 32]) !== 22 ||
            $signed(results[N*32 +: 32]) !== 43 ||
            $signed(results[(N+1)*32 +: 32]) !== 50) $fatal(1,"Directed example failed");
        $display("N=%0d example C=[[19,22],[43,50]] in top-left block",N);
        for (i=0;i<N;i=i+1)
            for (k=0;k<K_TILE;k=k+1) begin
                tile_a[i][k]=-128; tile_b[k][i]=-128;
            end
        run_tile(K_TILE,1);
        for (i=0;i<N;i=i+1)
            for (k=0;k<K_TILE;k=k+1) tile_b[k][i]=127;
        run_tile(K_TILE,1);
        // Tiling M/N and the reduction dimension K; combine partial sums on host.
        for (i=0;i<M*P;i=i+1) host_c[i]=0;
        for (ti=0;ti<M;ti=ti+N)
            for (tj=0;tj<P;tj=tj+N)
                for (tk=0;tk<K;tk=tk+K_TILE) begin
                    klen=(K-tk<K_TILE)?K-tk:K_TILE;
                    for (i=0;i<N;i=i+1)
                        for (k=0;k<K_TILE;k=k+1) begin
                            tile_a[i][k]=0;
                            if (ti+i<M && k<klen) tile_a[i][k]=a_mem[(ti+i)*K+tk+k];
                        end
                    for (k=0;k<K_TILE;k=k+1)
                        for (j=0;j<N;j=j+1) begin
                            tile_b[k][j]=0;
                            if (tj+j<P && k<klen) tile_b[k][j]=b_mem[(tk+k)*P+tj+j];
                        end
                    run_tile(klen,1);
                    for (i=0;i<N;i=i+1)
                        for (j=0;j<N;j=j+1)
                            if (ti+i<M && tj+j<P)
                                host_c[(ti+i)*P+tj+j]=host_c[(ti+i)*P+tj+j]+
                                    $signed(results[(i*N+j)*32 +: 32]);
                end
        for (i=0;i<M*P;i=i+1)
            if (host_c[i] !== golden[i])
                $fatal(1,"N=%0d tiled Python mismatch index=%0d got=%0d expected=%0d",
                    N,i,host_c[i],golden[i]);
        $display("PASS N=%0d: %0d tiles; Python golden 11x17 * 17x13; padding, K tiling, stalls",N,passes);
        finished=1;
    end
endmodule

module tb_systolic_array;
    wire done2,done4,done8;
    array_checker #(.N(2)) test2(done2);
    array_checker #(.N(4)) test4(done4);
    array_checker #(.N(8)) test8(done8);
    initial begin
        wait(done2 && done4 && done8);
        $display("PASS tb_systolic_array: all array sizes passed");
        $finish;
    end
    initial begin #5000000; $fatal(1,"Array watchdog timeout"); end
endmodule
