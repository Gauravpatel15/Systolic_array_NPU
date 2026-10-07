`timescale 1ns/1ps

module buffered_tile_engine #(
    parameter integer N = 8,
    parameter integer MAX_K = 8,
    parameter integer DATA_W = 8,
    parameter integer ADDR_W = $clog2(MAX_K),
    parameter integer BANK_W = $clog2(N),
    parameter integer LEN_W  = $clog2(MAX_K + 1),
    parameter integer STEP_W = $clog2(MAX_K + 2*N - 1)
) (
    input  wire                         clk,
    input  wire                         rst,

    // Start one N x N output tile.
    input  wire                         start,
    input  wire [LEN_W-1:0]             k_length,
    input  wire                         stall,

    // Activation tile loading interface.
    input  wire                         a_load_write_enable,
    input  wire [BANK_W-1:0]            a_load_bank,
    input  wire [ADDR_W-1:0]            a_load_addr,
    input  wire signed [DATA_W-1:0]     a_load_data,

    // Weight tile loading interface.
    input  wire                         b_load_write_enable,
    input  wire [BANK_W-1:0]            b_load_bank,
    input  wire [ADDR_W-1:0]            b_load_addr,
    input  wire signed [DATA_W-1:0]     b_load_data,

    output wire                         load_ready,
    output wire                         busy,
    output wire                         done,
    output wire                         error,

    output wire [N*N*32-1:0]            c_flat,

    // Debug signals.
    output wire [STEP_W-1:0]            debug_step_count,
    output wire [1:0]                   debug_state,
    output wire                         debug_array_ce
);

    wire controller_clear;

    wire [N-1:0] a_schedule_valid;
    wire [N-1:0] b_schedule_valid;

    // Controller uses LEN_W bits per bank.
    wire [N*LEN_W-1:0] a_k_index;
    wire [N*LEN_W-1:0] b_k_index;

    // Buffer needs ADDR_W bits per bank.
    wire [N*ADDR_W-1:0] a_buffer_read_addr;
    wire [N*ADDR_W-1:0] b_buffer_read_addr;

    wire [N*DATA_W-1:0] a_buffer_data;
    wire [N*DATA_W-1:0] b_buffer_data;

    wire [N-1:0] a_buffer_read_enable;
    wire [N-1:0] b_buffer_read_enable;

    wire feed_step_enable;

    wire [N-1:0] a_valid_to_array;
    wire [N-1:0] b_valid_to_array;

    wire [N*DATA_W-1:0] a_data_to_array;
    wire [N*DATA_W-1:0] b_data_to_array;

    wire array_ce;

    assign load_ready = !busy;

    // A controller FEED step requests reads from both buffers.
    assign feed_step_enable =
        (debug_state == 2'd2) && !stall;

    assign a_buffer_read_enable =
        a_schedule_valid & {N{feed_step_enable}};

    assign b_buffer_read_enable =
        b_schedule_valid & {N{feed_step_enable}};

    // Convert each controller address separately.
    // Do not connect N*LEN_W bits directly to N*ADDR_W bits.
    genvar bank;
    generate
        for (bank = 0; bank < N; bank = bank + 1) begin : gen_read_addr
            assign a_buffer_read_addr[bank*ADDR_W +: ADDR_W] =
                a_k_index[bank*LEN_W +: ADDR_W];

            assign b_buffer_read_addr[bank*ADDR_W +: ADDR_W] =
                b_k_index[bank*LEN_W +: ADDR_W];
        end
    endgenerate

    tile_controller #(
        .N(N),
        .MAX_K(MAX_K)
    ) controller (
        .clk(clk),
        .rst(rst),

        .start(start),
        .k_length(k_length),
        .stall(stall),

        .busy(busy),
        .done(done),
        .error(error),

        .array_clear(controller_clear),
        .array_ce(),

        .a_valid_left(a_schedule_valid),
        .b_valid_top(b_schedule_valid),

        .a_k_index(a_k_index),
        .b_k_index(b_k_index),

        .step_count(debug_step_count),
        .state(debug_state)
    );

    // Each activation-buffer bank stores one physical array row.
    banked_tile_buffer #(
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) activation_buffer (
        .clk(clk),
        .rst(rst),

        .load_write_enable(a_load_write_enable && load_ready),
        .load_bank(a_load_bank),
        .load_addr(a_load_addr),
        .load_data(a_load_data),

        .read_enable(a_buffer_read_enable),
        .read_addr(a_buffer_read_addr),

        .read_data(a_buffer_data)
    );

    // Each weight-buffer bank stores one physical array column.
    banked_tile_buffer #(
        .N(N),
        .MAX_K(MAX_K),
        .DATA_W(DATA_W)
    ) weight_buffer (
        .clk(clk),
        .rst(rst),

        .load_write_enable(b_load_write_enable && load_ready),
        .load_bank(b_load_bank),
        .load_addr(b_load_addr),
        .load_data(b_load_data),

        .read_enable(b_buffer_read_enable),
        .read_addr(b_buffer_read_addr),

        .read_data(b_buffer_data)
    );

    // Align buffer output data with array CE and valid signals.
    systolic_input_stage #(
        .N(N),
        .DATA_W(DATA_W)
    ) input_stage (
        .clk(clk),
        .rst(rst),
        .clear(controller_clear),

        .read_step_enable(feed_step_enable),

        .a_read_valid(a_buffer_read_enable),
        .b_read_valid(b_buffer_read_enable),

        .a_data_from_buffer(a_buffer_data),
        .b_data_from_buffer(b_buffer_data),

        .array_ce(array_ce),
        .a_valid_to_array(a_valid_to_array),
        .b_valid_to_array(b_valid_to_array),

        .a_data_to_array(a_data_to_array),
        .b_data_to_array(b_data_to_array)
    );

    systolic_array #(
        .N(N)
    ) array (
        .clk(clk),
        .rst(rst),
        .clear(controller_clear),
        .ce(array_ce),

        .a_left(a_data_to_array),
        .b_top(b_data_to_array),

        .a_valid_left(a_valid_to_array),
        .b_valid_top(b_valid_to_array),

        .c_flat(c_flat)
    );

    assign debug_array_ce = array_ce;

endmodule