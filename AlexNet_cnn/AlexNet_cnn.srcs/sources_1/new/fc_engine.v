`timescale 1ns / 1ps
`include "define_alexnet.vh"

module fc_engine #(
    parameter INPUT_SIZE     = 4,
    parameter OUTPUT_NEURONS = 3,

    parameter WEIGHT_FILE = "",
    parameter BIAS_FILE   = "",

    parameter signed [`REQUANT_MULT_WIDTH-1:0] REQUANT_MULTIPLIER = 32'sd1,
    parameter APPLY_RELU = 1
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    output wire [`ACTIVATION_ADDR_WIDTH-1:0] external_read_address,
    input  wire signed [`DATA_WIDTH-1:0]     external_read_data,

    output wire busy,
    output wire layer_done,

    output reg                          output_valid,
    output reg signed [`DATA_WIDTH-1:0] output_data,

    output reg [`CHANNEL_WIDTH-1:0] output_neuron_index,
    output reg [`ACTIVATION_ADDR_WIDTH-1:0] output_address
);

    // ============================================================
    // Loop-controller signals
    // ============================================================
    wire operation_valid;
    wire operation_ready;
    wire result_valid;

    wire [`FC_INPUT_INDEX_WIDTH-1:0] loop_input_index;
    wire [`CHANNEL_WIDTH-1:0]        loop_output_neuron;

    wire first_operation;
    wire last_operation;

    fc_controller #(
        .INPUT_SIZE     (INPUT_SIZE),
        .OUTPUT_NEURONS (OUTPUT_NEURONS)
    ) loop_ctrl_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),

        .operation_ready (operation_ready),
        .result_valid    (result_valid),

        .operation_valid (operation_valid),

        .input_index     (loop_input_index),
        .output_neuron   (loop_output_neuron),

        .first_operation (first_operation),
        .last_operation  (last_operation),

        .busy       (busy),
        .layer_done (layer_done)
    );

    // ============================================================
    // Address generator
    // ============================================================
    wire [`ACTIVATION_ADDR_WIDTH-1:0] input_address;
    wire [`WEIGHT_ADDR_WIDTH-1:0]     weight_address;
    wire [`BIAS_ADDR_WIDTH-1:0]       bias_address;

    fc_address_generator #(
        .INPUT_SIZE     (INPUT_SIZE),
        .OUTPUT_NEURONS (OUTPUT_NEURONS)
    ) addr_gen_inst (
        .input_index    (loop_input_index),
        .output_neuron  (loop_output_neuron),

        .input_address  (input_address),
        .weight_address (weight_address),
        .bias_address   (bias_address)
    );

    assign external_read_address = input_address;

    // ============================================================
    // Weight / bias ROMs (reused conv ROMs, KERNEL_SIZE=1 folds
    // the [filter][channel][kernel_row][kernel_col] layout down
    // to a flat [output_neuron][input_index] layout)
    // ============================================================
    wire signed [`WEIGHT_WIDTH-1:0] weight_rom_data;
    wire signed [`BIAS_WIDTH-1:0]   bias_rom_data;

    conv_weight_rom #(
        .INPUT_CHANNELS (INPUT_SIZE),
        .OUTPUT_FILTERS (OUTPUT_NEURONS),
        .KERNEL_SIZE    (1),
        .WEIGHT_FILE    (WEIGHT_FILE)
    ) weight_rom_inst (
        .clk            (clk),
        .weight_address (weight_address),
        .weight_out     (weight_rom_data)
    );

    conv_bias_rom #(
        .OUTPUT_FILTERS (OUTPUT_NEURONS),
        .BIAS_FILE      (BIAS_FILE)
    ) bias_rom_inst (
        .clk          (clk),
        .bias_address (bias_address),
        .bias_out     (bias_rom_data)
    );

    // ============================================================
    // Delay pipeline: ROM/buffer reads have 1-cycle latency, so
    // the control flags describing THIS data must be delayed
    // ============================================================
    reg operation_valid_d;
    reg first_operation_d;
    reg last_operation_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operation_valid_d <= 1'b0;
            first_operation_d <= 1'b0;
            last_operation_d  <= 1'b0;
        end
        else begin
            operation_valid_d <= operation_valid;
            first_operation_d <= operation_valid && first_operation;
            last_operation_d  <= operation_valid && last_operation;
        end
    end

    // ============================================================
    // MAC + requantize datapath
    // ============================================================
    wire signed [`DATA_WIDTH-1:0] datapath_result;

    fc_datapath datapath_inst (
        .clk             (clk),
        .rst_n           (rst_n),

        .operation_valid (operation_valid_d),
        .first_operation (first_operation_d),
        .last_operation  (last_operation_d),

        .input_data  (external_read_data),
        .weight_data (weight_rom_data),
        .bias_data   (bias_rom_data),

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
    // Remember which output neuron is being computed
    // ============================================================
    reg [`CHANNEL_WIDTH-1:0] pending_output_neuron;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_output_neuron <= 0;
        end
        else if (operation_valid && operation_ready && last_operation) begin
            pending_output_neuron <= loop_output_neuron;
        end
    end

    // ============================================================
    // Publish the completed result
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_valid         <= 1'b0;
            output_data          <= {`DATA_WIDTH{1'b0}};
            output_neuron_index  <= 0;
            output_address       <= 0;
        end
        else begin
            output_valid <= 1'b0;

            if (result_valid) begin
                output_valid <= 1'b1;
                output_data  <= datapath_result;

                output_neuron_index <= pending_output_neuron;
                output_address      <= pending_output_neuron;
            end
        end
    end

endmodule