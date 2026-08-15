`timescale 1ns / 1ps
`include "define_alexnet.vh"

module conv_datapath(
    input wire clk,
    input wire rst_n,

    // One activation/weight pair is valid this cycle
    input wire operation_valid,

    // First MAC of a new output value (reset the accumulator)
    input wire first_operation,

    // Final MAC of the current output value (add bias, finish up)
    input wire last_operation,

    input wire signed [`DATA_WIDTH-1:0]   activation,
    input wire signed [`WEIGHT_WIDTH-1:0] weight,
    input wire signed [`BIAS_WIDTH-1:0]   bias,

    // Q-format requantization parameters for this layer
    input wire signed [`REQUANT_MULT_WIDTH-1:0]  requant_multiplier,
    input wire        [`REQUANT_SHIFT_WIDTH-1:0] requant_shift,
    input wire                                    apply_relu,

    // This datapath can accept one operation every clock
    output wire operation_ready,

    // Completed, requantized output value
    output reg result_valid,
    output reg signed [`DATA_WIDTH-1:0] result_data,

    // Debug outputs: raw pre-requantize values, for waveform/
    // testbench inspection against golden .npy vectors
    output reg signed [`ACC_WIDTH-1:0] debug_accumulator,
    output reg signed [`ACC_WIDTH-1:0] debug_raw_result
);

    // ============================================================
    // This implementation accepts one operation every clock
    // ============================================================
    assign operation_ready = 1'b1;

    // ============================================================
    // Signed multiplication, widened to accumulator width
    // ============================================================
    localparam PRODUCT_WIDTH = `DATA_WIDTH + `WEIGHT_WIDTH;

    wire signed [PRODUCT_WIDTH-1:0] product;
    wire signed [`ACC_WIDTH-1:0]    product_extended;

    assign product = activation * weight;

    assign product_extended =
        {{(`ACC_WIDTH-PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};

    // ============================================================
    // Sequential accumulator
    // ============================================================
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
                    // A single-operation calculation is possible,
                    // so first and last may both be asserted at once
                    if (last_operation) begin
                        accumulator <= product_extended;
                        raw_result  <= product_extended + bias;
                        raw_valid   <= 1'b1;
                    end
                    else begin
                        accumulator <= product_extended;
                    end
                end
                else begin
                    if (last_operation) begin
                        accumulator <= accumulator + product_extended;
                        raw_result  <= accumulator + product_extended + bias;
                        raw_valid   <= 1'b1;
                    end
                    else begin
                        accumulator <= accumulator + product_extended;
                    end
                end
            end
        end
    end

    // ============================================================
    // Mirror internal accumulator/raw_result onto debug ports so
    // testbenches can inspect them without hierarchical references
    // ============================================================
    always @(*) begin
        debug_accumulator = accumulator;
        debug_raw_result  = raw_result;
    end

    // ============================================================
    // Requantize the raw INT32 accumulator down to INT8
    // ============================================================
    wire signed [`DATA_WIDTH-1:0] requantized_result;

    fixed_point_requantize requantize_inst (
        .accumulator (raw_result),
        .multiplier  (requant_multiplier),
        .shift       (requant_shift),
        .apply_relu  (apply_relu),
        .output_data (requantized_result)
    );

    // ============================================================
    // Publish the completed result one cycle after raw_valid,
    // matching the requantizer's combinational latency
    // ============================================================
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
