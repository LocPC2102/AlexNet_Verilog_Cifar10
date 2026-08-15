`timescale 1ns / 1ps
`include "define_alexnet.vh"

module fc_address_generator #(
    parameter INPUT_SIZE     = 4,
    parameter OUTPUT_NEURONS = 3
)(
    input wire [`FC_INPUT_INDEX_WIDTH-1:0] input_index,
    input wire [`CHANNEL_WIDTH-1:0]        output_neuron,

    output reg [`ACTIVATION_ADDR_WIDTH-1:0] input_address,
    output reg [`WEIGHT_ADDR_WIDTH-1:0]     weight_address,
    output reg [`BIAS_ADDR_WIDTH-1:0]       bias_address
);

    integer weight_calculation;

    always @(*) begin
        input_address = input_index;

        // Layout: [output_neuron][input_index]
        weight_calculation = output_neuron * INPUT_SIZE + input_index;
        weight_address      = weight_calculation;

        bias_address = output_neuron;
    end

endmodule