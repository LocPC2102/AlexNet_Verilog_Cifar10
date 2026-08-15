`timescale 1ns / 1ps
`include "define_alexnet.vh"

module pool_datapath(
    input wire clk,
    input wire rst_n,

    input wire element_valid,
    input wire first_element,
    input wire last_element,

    input wire signed [`DATA_WIDTH-1:0] activation_in,

    output wire element_ready,

    output reg result_valid,
    output reg signed [`DATA_WIDTH-1:0] result_out,

    // Debug: running max, for waveform/testbench inspection
    output reg signed [`DATA_WIDTH-1:0] debug_current_max
);

    assign element_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debug_current_max <= {`DATA_WIDTH{1'b0}};
            result_out        <= {`DATA_WIDTH{1'b0}};
            result_valid      <= 1'b0;
        end
        else begin
            result_valid <= 1'b0;

            if (element_valid && element_ready) begin

                if (first_element) begin
                    debug_current_max <= activation_in;

                    if (last_element) begin
                        result_out   <= activation_in;
                        result_valid <= 1'b1;
                    end
                end
                else begin
                    if (activation_in > debug_current_max)
                        debug_current_max <= activation_in;

                    if (last_element) begin
                        if (activation_in > debug_current_max)
                            result_out <= activation_in;
                        else
                            result_out <= debug_current_max;

                        result_valid <= 1'b1;
                    end
                end
            end
        end
    end

endmodule