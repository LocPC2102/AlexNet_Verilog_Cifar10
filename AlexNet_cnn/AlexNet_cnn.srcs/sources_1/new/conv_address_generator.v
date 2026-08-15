`timescale 1ns / 1ps
`include "define_alexnet.vh"

module conv_address_generator #(
    parameter INPUT_HEIGHT   = 5,
    parameter INPUT_WIDTH    = 5,
    parameter INPUT_CHANNELS = 3,
    parameter KERNEL_SIZE    = 3,
    parameter STRIDE         = 1,
    parameter PADDING        = 0
)(
    // Loop indices coming from conv_controller
    input wire [`ROW_COL_WIDTH-1:0] output_row,
    input wire [`ROW_COL_WIDTH-1:0] output_col,
    input wire [`CHANNEL_WIDTH-1:0] output_filter,
    input wire [`CHANNEL_WIDTH-1:0] input_channel,
    input wire [`KERNEL_WIDTH-1:0]  kernel_row,
    input wire [`KERNEL_WIDTH-1:0]  kernel_col,

    output reg [`ACTIVATION_ADDR_WIDTH-1:0] activation_address,
    output reg [`WEIGHT_ADDR_WIDTH-1:0]     weight_address,
    output reg [`BIAS_ADDR_WIDTH-1:0]       bias_address,

    // High when the requested activation position lies outside
    // the image (i.e. in the zero-padded border)
    output reg padding_active
);   

    localparam KERNEL_ELEMENTS = KERNEL_SIZE * KERNEL_SIZE;
    localparam CHANNEL_SIZE    = INPUT_HEIGHT * INPUT_WIDTH;

    integer activation_calc;
    integer weight_calc;
    
    reg signed [11:0] input_row;
    reg signed [11:0] input_col;

    always @(*) begin
        input_row = $signed({1'b0, output_row}) * STRIDE
                  + $signed({1'b0, kernel_row})
                  - PADDING;
        input_col = $signed({1'b0, output_col}) * STRIDE
                  + $signed({1'b0, kernel_col})
                  - PADDING;

        // Default values (avoid inferred latches)
        activation_address = 0;
        weight_address      = 0;
        bias_address        = output_filter;
        padding_active      = 1'b0;

        // ---- Activation address (or padding flag) ----
        if (input_row < 0 || input_row >= INPUT_HEIGHT ||
            input_col < 0 || input_col >= INPUT_WIDTH) begin

            padding_active      = 1'b1;
            activation_address  = 0;
        end
        else begin
            // Layout: [channel][row][col]
            activation_calc =
                input_channel * CHANNEL_SIZE
                + input_row * INPUT_WIDTH
                + input_col;

            activation_address = activation_calc;
        end

        // ---- Weight address ----
        // Layout: [filter][channel][kernel_row][kernel_col]
        weight_calc =
            output_filter * INPUT_CHANNELS * KERNEL_ELEMENTS
            + input_channel * KERNEL_ELEMENTS
            + kernel_row * KERNEL_SIZE
            + kernel_col;

        weight_address = weight_calc;
    end
endmodule
