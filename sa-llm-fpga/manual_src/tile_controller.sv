
`timescale 1ns/1ps

module tile_controller #(
    parameter integer N = 8,
    parameter integer MAX_K = 8,
    parameter integer LEN_W = $clog2(MAX_K + 1),
    parameter integer STEP_W = $clog2(MAX_K + 2*N - 1)
) (
    input  wire                     clk,
    input  wire                     rst,

    input  wire                     start,
    input  wire [LEN_W-1:0]         k_length,
    input  wire                     stall,

    output reg                      busy,
    output reg                      done,
    output reg                      error,

    output wire                     array_clear,
    output wire                     array_ce,

    output wire [N-1:0]             a_valid_left,
    output wire [N-1:0]             b_valid_top,

    output wire [N*LEN_W-1:0]       a_k_index,
    output wire [N*LEN_W-1:0]       b_k_index,

    output reg [STEP_W-1:0]         step_count,
    output reg [1:0]                state
);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_CLEAR = 2'd1;
    localparam [1:0] ST_FEED  = 2'd2;
    localparam [1:0] ST_DONE  = 2'd3;

    assign array_clear = (state == ST_CLEAR);

    assign array_ce =
        (state == ST_CLEAR) ||
        ((state == ST_FEED) && !stall);

    always @(posedge clk) begin
        if (rst) begin
            busy       <= 1'b0;
            done       <= 1'b0;
            error      <= 1'b0;
            step_count <= {STEP_W{1'b0}};
            state      <= ST_IDLE;
        end
        else begin
            done <= 1'b0;

            case (state)

                ST_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        if ((k_length == 0) ||
                            (k_length > MAX_K)) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                        end
                        else begin
                            busy       <= 1'b1;
                            error      <= 1'b0;
                            step_count <= {STEP_W{1'b0}};
                            state      <= ST_CLEAR;
                        end
                    end
                end

                ST_CLEAR: begin
                    step_count <= {STEP_W{1'b0}};
                    state      <= ST_FEED;
                end

                ST_FEED: begin
                    if (!stall) begin
                        if (step_count == k_length + 2*N - 3)
                            state <= ST_DONE;
                        else
                            step_count <= step_count + 1'b1;
                    end
                end

                ST_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    busy       <= 1'b0;
                    done       <= 1'b0;
                    error      <= 1'b1;
                    step_count <= {STEP_W{1'b0}};
                    state      <= ST_IDLE;
                end

            endcase
        end
    end

    genvar r, c;

    generate
        for (r = 0; r < N; r = r + 1) begin : gen_a_schedule

            assign a_valid_left[r] =
                (state == ST_FEED) &&
                (step_count >= r) &&
                (step_count < k_length + r);

            assign a_k_index[r*LEN_W +: LEN_W] =
                a_valid_left[r] ? step_count - r : {LEN_W{1'b0}};

        end

        for (c = 0; c < N; c = c + 1) begin : gen_b_schedule

            assign b_valid_top[c] =
                (state == ST_FEED) &&
                (step_count >= c) &&
                (step_count < k_length + c);

            assign b_k_index[c*LEN_W +: LEN_W] =
                b_valid_top[c] ? step_count - c : {LEN_W{1'b0}};

        end
    endgenerate

endmodule

