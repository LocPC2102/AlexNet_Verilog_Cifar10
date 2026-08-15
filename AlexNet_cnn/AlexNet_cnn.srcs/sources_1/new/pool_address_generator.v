`timescale 1ns / 1ps
`include "define_alexnet.vh"

module pool_address_generator #(
    parameter INPUT_HEIGHT = 5,
    parameter INPUT_WIDTH  = 5,
    parameter STRIDE       = 2
)(
    input wire [`ROW_COL_WIDTH-1:0] output_row,
    input wire [`ROW_COL_WIDTH-1:0] output_col,
    input wire [`CHANNEL_WIDTH-1:0] output_channel,

    input wire [`ROW_COL_WIDTH-1:0] pool_row,
    input wire [`ROW_COL_WIDTH-1:0] pool_col,

    output reg [`ACTIVATION_ADDR_WIDTH-1:0] activation_address,

    output reg [`ROW_COL_WIDTH-1:0] input_row,
    output reg [`ROW_COL_WIDTH-1:0] input_col
);

    localparam CHANNEL_SIZE = INPUT_HEIGHT * INPUT_WIDTH;

    integer address_calculation;

    always @(*) begin
        input_row = output_row * STRIDE + pool_row;
        input_col = output_col * STRIDE + pool_col;

        address_calculation =
            output_channel * CHANNEL_SIZE
            + input_row * INPUT_WIDTH
            + input_col;

        activation_address = address_calculation;
    end

endmodule