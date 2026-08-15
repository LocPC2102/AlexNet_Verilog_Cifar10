`timescale 1ns / 1ps
`include "define_alexnet.vh"

module alexnet_top (
    input wire clk,
    input wire rst_n,
    input wire start,

    output wire busy,
    output wire network_done,

    output wire                          final_output_valid,
    output wire signed [`DATA_WIDTH-1:0] final_output_data,
    output wire [`CHANNEL_WIDTH-1:0]     final_output_index,

    output wire [`NET_STATE_WIDTH-1:0] current_state,

    output wire                          prediction_valid,
    output wire [`CHANNEL_WIDTH-1:0]     predicted_class,
    output wire signed [`DATA_WIDTH-1:0] maximum_logit
);

    // ============================================================
    // Controller start / done signals
    // ============================================================
    wire conv1_start, pool1_start, conv2_start, pool2_start;
    wire conv3_start, conv4_start, conv5_start, pool5_start;
    wire fc6_start, fc7_start, fc8_start;

    wire conv1_done, pool1_done, conv2_done, pool2_done;
    wire conv3_done, conv4_done, conv5_done, pool5_done;
    wire fc6_done, fc7_done, fc8_done;

    // ============================================================
    // Conv1 (reads input_image.mem directly, no external buffer)
    // ============================================================
    wire                          conv1_output_valid;
    wire signed [`DATA_WIDTH-1:0] conv1_output_data;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] conv1_output_address;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] unused_conv1_read_address;

    wire [`ROW_COL_WIDTH-1:0] conv1_output_row;
    wire [`ROW_COL_WIDTH-1:0] conv1_output_col;
    wire [`CHANNEL_WIDTH-1:0] conv1_output_filter;

    // Buffer 1: Conv1 -> Pool1
    wire [`ACTIVATION_ADDR_WIDTH-1:0] pool1_read_address;
    wire signed [`DATA_WIDTH-1:0]     conv1_pool1_read_data;

    // Pool1 output
    wire                          pool1_output_valid;
    wire signed [`DATA_WIDTH-1:0] pool1_output_data;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] pool1_output_address;

    // Buffer 2: Pool1 -> Conv2
    wire [`ACTIVATION_ADDR_WIDTH-1:0] conv2_read_address;
    wire signed [`DATA_WIDTH-1:0]     pool1_conv2_read_data;

    // Conv2 output
    wire                          conv2_output_valid;
    wire signed [`DATA_WIDTH-1:0] conv2_output_data;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] conv2_output_address;

    // Buffer 3: Conv2 -> Pool2
    wire [`ACTIVATION_ADDR_WIDTH-1:0] pool2_read_address;
    wire signed [`DATA_WIDTH-1:0]     conv2_pool2_read_data;

    // Pool2 output
    wire                          pool2_output_valid;
    wire signed [`DATA_WIDTH-1:0] pool2_output_data;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] pool2_output_address;

    // Buffer 4: Pool2 -> Conv3
    wire [`ACTIVATION_ADDR_WIDTH-1:0] conv3_read_address;
    wire signed [`DATA_WIDTH-1:0]     pool2_conv3_read_data;

    // Conv3 output
    wire                          conv3_output_valid;
    wire signed [`DATA_WIDTH-1:0] conv3_output_data;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] conv3_output_address;

    // Buffer 5: Conv3 -> Conv4
    wire [`ACTIVATION_ADDR_WIDTH-1:0] conv4_read_address;
    wire signed [`DATA_WIDTH-1:0]     conv3_conv4_read_data;

    // Conv4 output
    wire                          conv4_output_valid;
    wire signed [`DATA_WIDTH-1:0] conv4_output_data;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] conv4_output_address;

    // Buffer 6: Conv4 -> Conv5
    wire [`ACTIVATION_ADDR_WIDTH-1:0] conv5_read_address;
    wire signed [`DATA_WIDTH-1:0]     conv4_conv5_read_data;

    // Conv5 output
    wire                          conv5_output_valid;
    wire signed [`DATA_WIDTH-1:0] conv5_output_data;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] conv5_output_address;

    // Buffer 7: Conv5 -> Pool5
    wire [`ACTIVATION_ADDR_WIDTH-1:0] pool5_read_address;
    wire signed [`DATA_WIDTH-1:0]     conv5_pool5_read_data;

    // Pool5 output
    wire                          pool5_output_valid;
    wire signed [`DATA_WIDTH-1:0] pool5_output_data;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] pool5_output_address;

    // Buffer 8: Pool5 -> FC6
    wire [`ACTIVATION_ADDR_WIDTH-1:0] fc6_read_address;
    wire signed [`DATA_WIDTH-1:0]     pool5_fc6_read_data;

    // FC6 output
    wire                          fc6_output_valid;
    wire signed [`DATA_WIDTH-1:0] fc6_output_data;
    wire [`CHANNEL_WIDTH-1:0]         fc6_output_index;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] fc6_output_address;

    // Buffer 9: FC6 -> FC7
    wire [`ACTIVATION_ADDR_WIDTH-1:0] fc7_read_address;
    wire signed [`DATA_WIDTH-1:0]     fc6_fc7_read_data;

    // FC7 output
    wire                          fc7_output_valid;
    wire signed [`DATA_WIDTH-1:0] fc7_output_data;
    wire [`CHANNEL_WIDTH-1:0]         fc7_output_index;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] fc7_output_address;

    // Buffer 10: FC7 -> FC8
    wire [`ACTIVATION_ADDR_WIDTH-1:0] fc8_read_address;
    wire signed [`DATA_WIDTH-1:0]     fc7_fc8_read_data;
    wire [`ACTIVATION_ADDR_WIDTH-1:0] fc8_output_address;

    // ============================================================
    // Network controller
    // ============================================================
    network_controller controller_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .start (start),

        .conv1_done (conv1_done), .pool1_done (pool1_done),
        .conv2_done (conv2_done), .pool2_done (pool2_done),
        .conv3_done (conv3_done), .conv4_done (conv4_done),
        .conv5_done (conv5_done), .pool5_done (pool5_done),
        .fc6_done   (fc6_done),   .fc7_done   (fc7_done),
        .fc8_done   (fc8_done),

        .conv1_start (conv1_start), .pool1_start (pool1_start),
        .conv2_start (conv2_start), .pool2_start (pool2_start),
        .conv3_start (conv3_start), .conv4_start (conv4_start),
        .conv5_start (conv5_start), .pool5_start (pool5_start),
        .fc6_start   (fc6_start),   .fc7_start   (fc7_start),
        .fc8_start   (fc8_start),

        .busy          (busy),
        .network_done  (network_done),
        .current_state (current_state)
    );

    // ============================================================
    // Conv1 - reads directly from input_image.mem
    // ============================================================
    conv_engine #(
        .INPUT_HEIGHT   (32), .INPUT_WIDTH   (32), .INPUT_CHANNELS (3),
        .OUTPUT_HEIGHT  (32), .OUTPUT_WIDTH  (32), .OUTPUT_FILTERS (8),
        .KERNEL_SIZE    (5),  .STRIDE        (1),  .PADDING        (2),
        .ACTIVATION_FILE    ("input_image_deer.mem"),
        .WEIGHT_FILE         ("conv1_weights.mem"),
        .BIAS_FILE            ("conv1_biases.mem"),
        .USE_EXTERNAL_INPUT   (0),
        .REQUANT_MULTIPLIER   (32'sd10468),
        .APPLY_RELU           (1)
    ) conv1_inst (
        .clk (clk), .rst_n (rst_n), .start (conv1_start),

        .external_read_address (unused_conv1_read_address),
        .external_read_data    ({`DATA_WIDTH{1'b0}}),

        .busy       (),
        .layer_done (conv1_done),

        .output_valid (conv1_output_valid),
        .output_data  (conv1_output_data),

        .output_row_index    (conv1_output_row),
        .output_col_index    (conv1_output_col),
        .output_filter_index (conv1_output_filter),

        .output_address (conv1_output_address)
    );

    activation_buffer #(.DEPTH(8192)) conv1_pool1_buffer (
        .clk (clk),
        .write_enable  (conv1_output_valid),
        .write_address (conv1_output_address),
        .write_data    (conv1_output_data),
        .read_address  (pool1_read_address),
        .read_data     (conv1_pool1_read_data)
    );

    // ============================================================
    // Pool1
    // ============================================================
    pool_engine #(
        .INPUT_HEIGHT (32), .INPUT_WIDTH (32), .CHANNELS (8),
        .OUTPUT_HEIGHT (16), .OUTPUT_WIDTH (16),
        .POOL_SIZE (2), .STRIDE (2)
    ) pool1_inst (
        .clk (clk), .rst_n (rst_n), .start (pool1_start),

        .external_read_address (pool1_read_address),
        .external_read_data    (conv1_pool1_read_data),

        .busy       (),
        .layer_done (pool1_done),

        .output_valid (pool1_output_valid),
        .output_data  (pool1_output_data),

        .output_row_index     (),
        .output_col_index     (),
        .output_channel_index (),

        .output_address (pool1_output_address)
    );

    activation_buffer #(.DEPTH(2048)) pool1_conv2_buffer (
        .clk (clk),
        .write_enable  (pool1_output_valid),
        .write_address (pool1_output_address),
        .write_data    (pool1_output_data),
        .read_address  (conv2_read_address),
        .read_data     (pool1_conv2_read_data)
    );

    // ============================================================
    // Conv2
    // ============================================================
    conv_engine #(
        .INPUT_HEIGHT (16), .INPUT_WIDTH (16), .INPUT_CHANNELS (8),
        .OUTPUT_HEIGHT (16), .OUTPUT_WIDTH (16), .OUTPUT_FILTERS (16),
        .KERNEL_SIZE (3), .STRIDE (1), .PADDING (1),
        .WEIGHT_FILE          ("conv2_weights.mem"),
        .BIAS_FILE            ("conv2_biases.mem"),
        .USE_EXTERNAL_INPUT   (1),
        .REQUANT_MULTIPLIER   (32'sd42589),
        .APPLY_RELU           (1)
    ) conv2_inst (
        .clk (clk), .rst_n (rst_n), .start (conv2_start),

        .external_read_address (conv2_read_address),
        .external_read_data    (pool1_conv2_read_data),

        .busy       (),
        .layer_done (conv2_done),

        .output_valid (conv2_output_valid),
        .output_data  (conv2_output_data),

        .output_row_index    (),
        .output_col_index    (),
        .output_filter_index (),

        .output_address (conv2_output_address)
    );

    activation_buffer #(.DEPTH(4096)) conv2_pool2_buffer (
        .clk (clk),
        .write_enable  (conv2_output_valid),
        .write_address (conv2_output_address),
        .write_data    (conv2_output_data),
        .read_address  (pool2_read_address),
        .read_data     (conv2_pool2_read_data)
    );

    // ============================================================
    // Pool2
    // ============================================================
    pool_engine #(
        .INPUT_HEIGHT (16), .INPUT_WIDTH (16), .CHANNELS (16),
        .OUTPUT_HEIGHT (8), .OUTPUT_WIDTH (8),
        .POOL_SIZE (2), .STRIDE (2)
    ) pool2_inst (
        .clk (clk), .rst_n (rst_n), .start (pool2_start),

        .external_read_address (pool2_read_address),
        .external_read_data    (conv2_pool2_read_data),

        .busy       (),
        .layer_done (pool2_done),

        .output_valid (pool2_output_valid),
        .output_data  (pool2_output_data),

        .output_row_index     (),
        .output_col_index     (),
        .output_channel_index (),

        .output_address (pool2_output_address)
    );

    activation_buffer #(.DEPTH(1024)) pool2_conv3_buffer (
        .clk (clk),
        .write_enable  (pool2_output_valid),
        .write_address (pool2_output_address),
        .write_data    (pool2_output_data),
        .read_address  (conv3_read_address),
        .read_data     (pool2_conv3_read_data)
    );

    // ============================================================
    // Conv3
    // ============================================================
    conv_engine #(
        .INPUT_HEIGHT (8), .INPUT_WIDTH (8), .INPUT_CHANNELS (16),
        .OUTPUT_HEIGHT (8), .OUTPUT_WIDTH (8), .OUTPUT_FILTERS (32),
        .KERNEL_SIZE (3), .STRIDE (1), .PADDING (1),
        .WEIGHT_FILE          ("conv3_weights.mem"),
        .BIAS_FILE            ("conv3_biases.mem"),
        .USE_EXTERNAL_INPUT   (1),
        .REQUANT_MULTIPLIER   (32'sd86904),
        .APPLY_RELU           (1)
    ) conv3_inst (
        .clk (clk), .rst_n (rst_n), .start (conv3_start),

        .external_read_address (conv3_read_address),
        .external_read_data    (pool2_conv3_read_data),

        .busy       (),
        .layer_done (conv3_done),

        .output_valid (conv3_output_valid),
        .output_data  (conv3_output_data),

        .output_row_index    (),
        .output_col_index    (),
        .output_filter_index (),

        .output_address (conv3_output_address)
    );

    activation_buffer #(.DEPTH(2048)) conv3_conv4_buffer (
        .clk (clk),
        .write_enable  (conv3_output_valid),
        .write_address (conv3_output_address),
        .write_data    (conv3_output_data),
        .read_address  (conv4_read_address),
        .read_data     (conv3_conv4_read_data)
    );

    // ============================================================
    // Conv4
    // ============================================================
    conv_engine #(
        .INPUT_HEIGHT (8), .INPUT_WIDTH (8), .INPUT_CHANNELS (32),
        .OUTPUT_HEIGHT (8), .OUTPUT_WIDTH (8), .OUTPUT_FILTERS (32),
        .KERNEL_SIZE (3), .STRIDE (1), .PADDING (1),
        .WEIGHT_FILE          ("conv4_weights.mem"),
        .BIAS_FILE            ("conv4_biases.mem"),
        .USE_EXTERNAL_INPUT   (1),
        .REQUANT_MULTIPLIER   (32'sd68286),
        .APPLY_RELU           (1)
    ) conv4_inst (
        .clk (clk), .rst_n (rst_n), .start (conv4_start),

        .external_read_address (conv4_read_address),
        .external_read_data    (conv3_conv4_read_data),

        .busy       (),
        .layer_done (conv4_done),

        .output_valid (conv4_output_valid),
        .output_data  (conv4_output_data),

        .output_row_index    (),
        .output_col_index    (),
        .output_filter_index (),

        .output_address (conv4_output_address)
    );

    activation_buffer #(.DEPTH(2048)) conv4_conv5_buffer (
        .clk (clk),
        .write_enable  (conv4_output_valid),
        .write_address (conv4_output_address),
        .write_data    (conv4_output_data),
        .read_address  (conv5_read_address),
        .read_data     (conv4_conv5_read_data)
    );

    // ============================================================
    // Conv5
    // ============================================================
    conv_engine #(
        .INPUT_HEIGHT (8), .INPUT_WIDTH (8), .INPUT_CHANNELS (32),
        .OUTPUT_HEIGHT (8), .OUTPUT_WIDTH (8), .OUTPUT_FILTERS (16),
        .KERNEL_SIZE (3), .STRIDE (1), .PADDING (1),
        .WEIGHT_FILE          ("conv5_weights.mem"),
        .BIAS_FILE            ("conv5_biases.mem"),
        .USE_EXTERNAL_INPUT   (1),
        .REQUANT_MULTIPLIER   (32'sd62822),
        .APPLY_RELU           (1)
    ) conv5_inst (
        .clk (clk), .rst_n (rst_n), .start (conv5_start),

        .external_read_address (conv5_read_address),
        .external_read_data    (conv4_conv5_read_data),

        .busy       (),
        .layer_done (conv5_done),

        .output_valid (conv5_output_valid),
        .output_data  (conv5_output_data),

        .output_row_index    (),
        .output_col_index    (),
        .output_filter_index (),

        .output_address (conv5_output_address)
    );

    activation_buffer #(.DEPTH(1024)) conv5_pool5_buffer (
        .clk (clk),
        .write_enable  (conv5_output_valid),
        .write_address (conv5_output_address),
        .write_data    (conv5_output_data),
        .read_address  (pool5_read_address),
        .read_data     (conv5_pool5_read_data)
    );

    // ============================================================
    // Pool5
    // ============================================================
    pool_engine #(
        .INPUT_HEIGHT (8), .INPUT_WIDTH (8), .CHANNELS (16),
        .OUTPUT_HEIGHT (4), .OUTPUT_WIDTH (4),
        .POOL_SIZE (2), .STRIDE (2)
    ) pool5_inst (
        .clk (clk), .rst_n (rst_n), .start (pool5_start),

        .external_read_address (pool5_read_address),
        .external_read_data    (conv5_pool5_read_data),

        .busy       (),
        .layer_done (pool5_done),

        .output_valid (pool5_output_valid),
        .output_data  (pool5_output_data),

        .output_row_index     (),
        .output_col_index     (),
        .output_channel_index (),

        .output_address (pool5_output_address)
    );

    activation_buffer #(.DEPTH(256)) pool5_fc6_buffer (
        .clk (clk),
        .write_enable  (pool5_output_valid),
        .write_address (pool5_output_address),
        .write_data    (pool5_output_data),
        .read_address  (fc6_read_address),
        .read_data     (pool5_fc6_read_data)
    );

    // ============================================================
    // FC6
    // ============================================================
    fc_engine #(
        .INPUT_SIZE (256), .OUTPUT_NEURONS (64),
        .WEIGHT_FILE        ("fc6_weights.mem"),
        .BIAS_FILE          ("fc6_biases.mem"),
        .REQUANT_MULTIPLIER (32'sd64619),
        .APPLY_RELU         (1)
    ) fc6_inst (
        .clk (clk), .rst_n (rst_n), .start (fc6_start),

        .external_read_address (fc6_read_address),
        .external_read_data    (pool5_fc6_read_data),

        .busy       (),
        .layer_done (fc6_done),

        .output_valid (fc6_output_valid),
        .output_data  (fc6_output_data),

        .output_neuron_index (fc6_output_index),
        .output_address      (fc6_output_address)
    );

    activation_buffer #(.DEPTH(64)) fc6_fc7_buffer (
        .clk (clk),
        .write_enable  (fc6_output_valid),
        .write_address (fc6_output_address),
        .write_data    (fc6_output_data),
        .read_address  (fc7_read_address),
        .read_data     (fc6_fc7_read_data)
    );

    // ============================================================
    // FC7
    // ============================================================
    fc_engine #(
        .INPUT_SIZE (64), .OUTPUT_NEURONS (32),
        .WEIGHT_FILE        ("fc7_weights.mem"),
        .BIAS_FILE          ("fc7_biases.mem"),
        .REQUANT_MULTIPLIER (32'sd66473),
        .APPLY_RELU         (1)
    ) fc7_inst (
        .clk (clk), .rst_n (rst_n), .start (fc7_start),

        .external_read_address (fc7_read_address),
        .external_read_data    (fc6_fc7_read_data),

        .busy       (),
        .layer_done (fc7_done),

        .output_valid (fc7_output_valid),
        .output_data  (fc7_output_data),

        .output_neuron_index (fc7_output_index),
        .output_address      (fc7_output_address)
    );

    activation_buffer #(.DEPTH(32)) fc7_fc8_buffer (
        .clk (clk),
        .write_enable  (fc7_output_valid),
        .write_address (fc7_output_address),
        .write_data    (fc7_output_data),
        .read_address  (fc8_read_address),
        .read_data     (fc7_fc8_read_data)
    );

    // ============================================================
    // FC8 - ReLU disabled to preserve negative logits
    // ============================================================
    fc_engine #(
        .INPUT_SIZE (32), .OUTPUT_NEURONS (10),
        .WEIGHT_FILE        ("fc8_weights.mem"),
        .BIAS_FILE          ("fc8_biases.mem"),
        .REQUANT_MULTIPLIER (32'sd141491),
        .APPLY_RELU         (0)
    ) fc8_inst (
        .clk (clk), .rst_n (rst_n), .start (fc8_start),

        .external_read_address (fc8_read_address),
        .external_read_data    (fc7_fc8_read_data),

        .busy       (),
        .layer_done (fc8_done),

        .output_valid (final_output_valid),
        .output_data  (final_output_data),

        .output_neuron_index (final_output_index),
        .output_address      (fc8_output_address)
    );

    // ============================================================
    // Argmax
    // ============================================================
    wire argmax_busy;
    wire argmax_input_done;

    assign argmax_input_done =
        final_output_valid && (final_output_index == 9);

    argmax_engine argmax_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .start (fc8_start),

        .input_valid (final_output_valid),
        .input_index (final_output_index),
        .input_data  (final_output_data),

        .input_done (argmax_input_done),

        .busy (argmax_busy),

        .prediction_valid (prediction_valid),
        .predicted_class  (predicted_class),
        .maximum_logit    (maximum_logit)
    );

endmodule