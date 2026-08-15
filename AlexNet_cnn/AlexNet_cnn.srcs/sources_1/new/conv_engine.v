`timescale 1ns / 1ps
`include "define_alexnet.vh"

module conv_engine #(
    parameter INPUT_HEIGHT   = 5,
    parameter INPUT_WIDTH    = 5,
    parameter INPUT_CHANNELS = 1,

    parameter OUTPUT_HEIGHT  = 3,
    parameter OUTPUT_WIDTH   = 3,
    parameter OUTPUT_FILTERS = 1,

    parameter KERNEL_SIZE    = 3,
    parameter STRIDE         = 1,
    parameter PADDING        = 0,

    parameter ACTIVATION_FILE = "",
    parameter WEIGHT_FILE     = "",
    parameter BIAS_FILE       = "",
    parameter USE_EXTERNAL_INPUT = 0,

    parameter signed [`REQUANT_MULT_WIDTH-1:0] REQUANT_MULTIPLIER = 32'sd1,
    parameter APPLY_RELU = 1
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    // Read port into an external activation_buffer
    output wire [`ACTIVATION_ADDR_WIDTH-1:0] external_read_address,
    input  wire signed [`DATA_WIDTH-1:0]     external_read_data,

    output wire busy,
    output wire layer_done,

    output reg                          output_valid,
    output reg signed [`DATA_WIDTH-1:0] output_data,

    output reg [`ROW_COL_WIDTH-1:0] output_row_index,
    output reg [`ROW_COL_WIDTH-1:0] output_col_index,
    output reg [`CHANNEL_WIDTH-1:0] output_filter_index,

    output reg [`ACTIVATION_ADDR_WIDTH-1:0] output_address
);

    // ============================================================
    // Loop-controller <-> address-generator wires
    // ============================================================
    wire operation_valid;
    wire operation_ready;
    wire result_valid;

    wire [`ROW_COL_WIDTH-1:0] loop_output_row;
    wire [`ROW_COL_WIDTH-1:0] loop_output_col;
    wire [`CHANNEL_WIDTH-1:0] loop_output_filter;
    wire [`CHANNEL_WIDTH-1:0] loop_input_channel;
    wire [`KERNEL_WIDTH-1:0]  loop_kernel_row;
    wire [`KERNEL_WIDTH-1:0]  loop_kernel_col;

    wire first_operation;
    wire last_operation;

    conv_controller #(
        .OUTPUT_HEIGHT  (OUTPUT_HEIGHT),
        .OUTPUT_WIDTH   (OUTPUT_WIDTH),
        .OUTPUT_FILTERS (OUTPUT_FILTERS),
        .INPUT_CHANNELS (INPUT_CHANNELS),
        .KERNEL_SIZE    (KERNEL_SIZE)
    ) loop_ctrl_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),

        .operation_ready (operation_ready),
        .result_valid    (result_valid),

        .operation_valid (operation_valid),

        .output_row      (loop_output_row),
        .output_col      (loop_output_col),
        .output_filter   (loop_output_filter),
        .input_channel   (loop_input_channel),
        .kernel_row      (loop_kernel_row),
        .kernel_col      (loop_kernel_col),

        .first_operation (first_operation),
        .last_operation  (last_operation),

        .busy              (busy),
        .output_value_done (),
        .layer_done        (layer_done)
    );

    // ============================================================
    // Address generator
    // ============================================================
    wire [`ACTIVATION_ADDR_WIDTH-1:0] activation_address;
    wire [`WEIGHT_ADDR_WIDTH-1:0]     weight_address;
    wire [`BIAS_ADDR_WIDTH-1:0]       bias_address;
    wire                              padding_active;

    conv_address_generator #(
        .INPUT_HEIGHT   (INPUT_HEIGHT),
        .INPUT_WIDTH    (INPUT_WIDTH),
        .INPUT_CHANNELS (INPUT_CHANNELS),
        .KERNEL_SIZE    (KERNEL_SIZE),
        .STRIDE         (STRIDE),
        .PADDING        (PADDING)
    ) addr_gen_inst (
        .output_row     (loop_output_row),
        .output_col     (loop_output_col),
        .output_filter  (loop_output_filter),
        .input_channel  (loop_input_channel),
        .kernel_row     (loop_kernel_row),
        .kernel_col     (loop_kernel_col),

        .activation_address (activation_address),
        .weight_address     (weight_address),
        .bias_address       (bias_address),
        .padding_active     (padding_active)
    );

    assign external_read_address = activation_address;

    // ============================================================
    // ROMs
    // ============================================================
    wire signed [`DATA_WIDTH-1:0]   activation_rom_data;
    wire signed [`WEIGHT_WIDTH-1:0] weight_rom_data;
    wire signed [`BIAS_WIDTH-1:0]   bias_rom_data;

    conv_activation_rom #(
        .INPUT_HEIGHT    (INPUT_HEIGHT),
        .INPUT_WIDTH     (INPUT_WIDTH),
        .INPUT_CHANNELS  (INPUT_CHANNELS),
        .ACTIVATION_FILE (ACTIVATION_FILE)
    ) activation_rom_inst (
        .clk                (clk),
        .activation_address (activation_address),
        .padding_active     (1'b0), 
        .activation_out     (activation_rom_data)
    );

    conv_weight_rom #(
        .INPUT_CHANNELS (INPUT_CHANNELS),
        .OUTPUT_FILTERS (OUTPUT_FILTERS),
        .KERNEL_SIZE    (KERNEL_SIZE),
        .WEIGHT_FILE    (WEIGHT_FILE)
    ) weight_rom_inst (
        .clk            (clk),
        .weight_address (weight_address),
        .weight_out     (weight_rom_data)
    );

    conv_bias_rom #(
        .OUTPUT_FILTERS (OUTPUT_FILTERS),
        .BIAS_FILE      (BIAS_FILE)
    ) bias_rom_inst (
        .clk          (clk),
        .bias_address (bias_address),
        .bias_out     (bias_rom_data)
    );

    // ============================================================
    // Delay pipeline: ROMs are synchronous (1-cycle read latency)
    // ============================================================
    reg operation_valid_d;
    reg first_operation_d;
    reg last_operation_d;
    reg padding_active_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operation_valid_d <= 1'b0;
            first_operation_d <= 1'b0;
            last_operation_d  <= 1'b0;
            padding_active_d  <= 1'b0;
        end
        else begin
            operation_valid_d <= operation_valid;
            first_operation_d <= operation_valid && first_operation;
            last_operation_d  <= operation_valid && last_operation;
            padding_active_d  <= operation_valid && padding_active;
        end
    end

    // Activation actually fed into the datapath this cycle: zero
    wire signed [`DATA_WIDTH-1:0] selected_activation;

    assign selected_activation =
        padding_active_d
            ? {`DATA_WIDTH{1'b0}}
            : (USE_EXTERNAL_INPUT ? external_read_data : activation_rom_data);

    // ============================================================
    // MAC + requantize datapath
    // ============================================================
    wire signed [`DATA_WIDTH-1:0] datapath_result;

    conv_datapath datapath_inst (
        .clk             (clk),
        .rst_n           (rst_n),

        .operation_valid (operation_valid_d),
        .first_operation (first_operation_d),
        .last_operation  (last_operation_d),

        .activation (selected_activation),
        .weight     (weight_rom_data),
        .bias       (bias_rom_data),

        .requant_multiplier (REQUANT_MULTIPLIER),
        .requant_shift      (`REQUANT_SHIFT_VALUE),
        .apply_relu         (APPLY_RELU),

        .operation_ready (operation_ready),

        .result_valid (result_valid),
        .result_data  (datapath_result),

        .debug_accumulator (),
        .debug_raw_result  ()
    );

    // ============================================================
    // Remember which output value is being computed, captured at
    // the moment the loop controller accepts its last operation
    // ============================================================
    reg [`ROW_COL_WIDTH-1:0] pending_output_row;
    reg [`ROW_COL_WIDTH-1:0] pending_output_col;
    reg [`CHANNEL_WIDTH-1:0] pending_output_filter;
    reg [`ACTIVATION_ADDR_WIDTH-1:0] pending_output_address;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_output_row     <= 0;
            pending_output_col     <= 0;
            pending_output_filter  <= 0;
            pending_output_address <= 0;
        end
        else if (operation_valid && operation_ready && last_operation) begin
            pending_output_row    <= loop_output_row;
            pending_output_col    <= loop_output_col;
            pending_output_filter <= loop_output_filter;

            pending_output_address <=
                loop_output_filter * OUTPUT_HEIGHT * OUTPUT_WIDTH
                + loop_output_row * OUTPUT_WIDTH
                + loop_output_col;
        end
    end

    // ============================================================
    // Publish the completed, requantized output value
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_valid         <= 1'b0;
            output_data          <= {`DATA_WIDTH{1'b0}};
            output_row_index     <= 0;
            output_col_index     <= 0;
            output_filter_index  <= 0;
            output_address       <= 0;
        end
        else begin
            output_valid <= 1'b0;

            if (result_valid) begin
                output_valid <= 1'b1;
                output_data  <= datapath_result;

                output_row_index    <= pending_output_row;
                output_col_index    <= pending_output_col;
                output_filter_index <= pending_output_filter;
                output_address      <= pending_output_address;
            end
        end
    end

endmodule
