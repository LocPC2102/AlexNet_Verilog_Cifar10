`timescale 1ns / 1ps
`include "define_alexnet.vh"

module conv_bias_rom #(
    parameter OUTPUT_FILTERS = 2,
    parameter BIAS_FILE      = ""
)(
    input wire clk,
    input wire [`BIAS_ADDR_WIDTH-1:0] bias_address,

    output reg signed [`BIAS_WIDTH-1:0] bias_out
);

    reg signed [`BIAS_WIDTH-1:0]
        bias_memory [0:OUTPUT_FILTERS-1];

    integer i;

    initial begin
        for (i = 0; i < OUTPUT_FILTERS; i = i + 1)
            bias_memory[i] = 0;

        if (BIAS_FILE != "") begin
            $display("Loading bias file: %s", BIAS_FILE);
            $readmemh(BIAS_FILE, bias_memory);
        end
        else begin
            $display("No bias file supplied; using zeros.");
        end
    end

    always @(posedge clk) begin
        if (bias_address < OUTPUT_FILTERS)
            bias_out <= bias_memory[bias_address];
        else
            bias_out <= {`BIAS_WIDTH{1'b0}};
    end

endmodule
