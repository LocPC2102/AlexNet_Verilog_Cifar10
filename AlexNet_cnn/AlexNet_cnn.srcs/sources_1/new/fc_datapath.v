`timescale 1ns / 1ps
`include "define_alexnet.vh"

module fc_datapath(
    input wire clk,
    input wire rst_n,

    input wire operation_valid,
    input wire first_operation,
    input wire last_operation,

    input wire signed [`DATA_WIDTH-1:0]   input_data,
    input wire signed [`WEIGHT_WIDTH-1:0] weight_data,
    input wire signed [`BIAS_WIDTH-1:0]   bias_data,

    input wire signed [`REQUANT_MULT_WIDTH-1:0]  requant_multiplier,
    input wire        [`REQUANT_SHIFT_WIDTH-1:0] requant_shift,
    input wire                                    apply_relu,

    output wire operation_ready,

    output reg result_valid,
    output reg signed [`DATA_WIDTH-1:0] result_data,

    output reg signed [`ACC_WIDTH-1:0] debug_accumulator,
    output reg signed [`ACC_WIDTH-1:0] debug_raw_result
);

    assign operation_ready = 1'b1;

    localparam PRODUCT_WIDTH = `DATA_WIDTH + `WEIGHT_WIDTH;

    wire signed [PRODUCT_WIDTH-1:0] product;
    wire signed [`ACC_WIDTH-1:0]    product_extended;

    assign product = input_data * weight_data;

    assign product_extended =
        {{(`ACC_WIDTH-PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};

    reg signed [`ACC_WIDTH-1:0] accumulator;
    reg signed [`ACC_WIDTH-1:0] raw_result;
    reg                         raw_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= {`ACC_WIDTH{1'b0}};
            raw_result  <= {`ACC_WIDTH{1'b0}};
            raw_valid   <= 1'b0;
        end
        else begin
            raw_valid <= 1'b0;

            if (operation_valid && operation_ready) begin

                if (first_operation) begin
                    if (last_operation) begin
                        accumulator <= product_extended;
                        raw_result  <= product_extended + bias_data;
                        raw_valid   <= 1'b1;
                    end
                    else begin
                        accumulator <= product_extended;
                    end
                end
                else begin
                    if (last_operation) begin
                        accumulator <= accumulator + product_extended;
                        raw_result  <= accumulator + product_extended + bias_data;
                        raw_valid   <= 1'b1;
                    end
                    else begin
                        accumulator <= accumulator + product_extended;
                    end
                end
            end
        end
    end

    always @(*) begin
        debug_accumulator = accumulator;
        debug_raw_result  = raw_result;
    end

    wire signed [`DATA_WIDTH-1:0] requantized_result;

    fixed_point_requantize requantize_inst (
        .accumulator (raw_result),
        .multiplier  (requant_multiplier),
        .shift       (requant_shift),
        .apply_relu  (apply_relu),
        .output_data (requantized_result)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_valid <= 1'b0;
            result_data  <= {`DATA_WIDTH{1'b0}};
        end
        else begin
            result_valid <= raw_valid;
            result_data  <= requantized_result;
        end
    end

endmodule