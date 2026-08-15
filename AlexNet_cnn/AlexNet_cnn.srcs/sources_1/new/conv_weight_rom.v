`timescale 1ns / 1ps
`include "define_alexnet.vh"

module conv_weight_rom #(
    parameter INPUT_CHANNELS = 3,
    parameter OUTPUT_FILTERS = 2,
    parameter KERNEL_SIZE    = 3,
    parameter WEIGHT_FILE    = ""
)(
    input wire clk,
    input wire [`WEIGHT_ADDR_WIDTH-1:0] weight_address,

    output reg signed [`WEIGHT_WIDTH-1:0] weight_out
);

    localparam KERNEL_ELEMENTS = KERNEL_SIZE * KERNEL_SIZE;
    localparam TOTAL_WEIGHTS   =
        OUTPUT_FILTERS * INPUT_CHANNELS * KERNEL_ELEMENTS;

    reg signed [`WEIGHT_WIDTH-1:0]
        weight_memory [0:TOTAL_WEIGHTS-1];

    integer i;

    initial begin
        for (i = 0; i < TOTAL_WEIGHTS; i = i + 1)
            weight_memory[i] = 0;

        if (WEIGHT_FILE != "") begin
            $display("Loading weight file: %s", WEIGHT_FILE);
            $readmemh(WEIGHT_FILE, weight_memory);
        end
        else begin
            $display("No weight file supplied; using zeros.");
        end
    end

    always @(posedge clk) begin
        if (weight_address < TOTAL_WEIGHTS)
            weight_out <= weight_memory[weight_address];
        else
            weight_out <= {`WEIGHT_WIDTH{1'b0}};
    end

endmodule
