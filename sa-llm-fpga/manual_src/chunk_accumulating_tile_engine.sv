
`timescale 1ns/1ps

module chunk_accumulating_tile_engine #(
    parameter integer N = 8,
    parameter integer MAX_K = 8,
    parameter integer DATA_W = 8,
    parameter integer ADDR_W = $clog2(MAX_K),
    parameter integer BANK_W = $clog2(N),
    parameter integer LEN_W  = $clog2(MAX_K + 1)
) (
    input  wire                         clk,
    input  wire                         rst,

    input  wire                         clear_output,

    input  wire                         start,
    input  wire [LEN_W-1:0]             k_length,
    input  wire                         accumulate,
    input  wire                         stall,

    input  wire                         a_load_write_enable,
    input  wire [BANK_W-1:0]            a_load_bank,
    input  wire [ADDR_W-1:0]            a_load_addr,
    input  wire signed [DATA_W-1:0]     a_load_data,

    input  wire                         b_load_write_enable,
    input  wire [BANK_W-1:0]            b_load_bank,
    input  wire [ADDR_W-1:0]            b_load_addr,
    input  wire signed [DATA_W-1:0]     b_load_data,

    output wire                         load_ready,
    output wire                         busy,
    output reg                          done,
    output wire                         error,

    output wire [N*N*32-1:0]            c_tile
);

    wire engine_done;
    wire engine_error;
    wire [N*N*32-1:0] engine_c_flat;

    reg accumulate_latched;

    always @(posedge clk) begin
        if (rst) begin
            done               <= 1'b0;
            accumulate_latched <= 1'b0;
        end
        else begin
            done <= engine_done;

            if (clear_output)
                accumulate_latched <= 1'b0;
            else if (start && load_ready)
                accumulate_latched <= accumulate;
        end
    end

    buffered_tile_engine #(
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) engine (
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
        .done(engine_done),
        .error(engine_error),

        .c_flat(engine_c_flat),

        .debug_step_count(),
        .debug_state(),
        .debug_array_ce()
    );

    output_tile_accumulator #(
        .N(N)
    ) accumulator (
        .clk(clk),
        .rst(rst),
        .clear(clear_output),

        .write_enable(engine_done && !engine_error),
        .accumulate(accumulate_latched),

        .tile_result(engine_c_flat),
        .c_tile(c_tile)
    );

    assign error = engine_error;

endmodule

