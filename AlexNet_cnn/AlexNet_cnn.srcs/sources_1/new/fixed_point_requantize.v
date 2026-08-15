`timescale 1ns / 1ps
`include "define_alexnet.vh"

module fixed_point_requantize(
        input wire signed [`ACC_WIDTH-1:0]           accumulator,
        input wire signed [`REQUANT_MULT_WIDTH-1:0]  multiplier,
        input wire        [`REQUANT_SHIFT_WIDTH-1:0] shift,
        input wire                                   apply_relu,
        
        output reg signed [`DATA_WIDTH-1:0]          output_data
       
    );
    
    reg signed [63:0] product;      // product = accumulator x multiplier
    reg [63:0] absolute_product;    // |product|
    reg [63:0] quotient;            // 
    reg [63:0] remainder;
    reg [63:0] remainder_mask;
    reg [63:0] half_value;
    reg [63:0] rounded_magnitude;

    reg signed [64:0] scaled_value;
    
    
    always @(*) begin
        // ---- Step 1: multiply ----
        product = accumulator * multiplier;

        // ---- Step 2a: work on the unsigned magnitude ----
        if (product < 0)
            absolute_product = -product;
        else
            absolute_product = product;

        // Integer division by 2^shift via shift/mask (cheaper than / and %)
        quotient = absolute_product >> shift;

        remainder_mask = (64'h1 << shift) - 1'b1;
        remainder = absolute_product & remainder_mask;

        half_value = 64'h1 << (shift - 1'b1);

        // ---- Step 2b: round to nearest, ties to even ----
        if (remainder > half_value) begin
            // more than halfway -> always round up
            rounded_magnitude = quotient + 1'b1;
        end
        else if (remainder == half_value && quotient[0] == 1'b1) begin
            // exactly halfway AND quotient is odd -> round up to make it even
            rounded_magnitude = quotient + 1'b1;
        end
        else begin
            // less than halfway, or exact tie already even -> round down
            rounded_magnitude = quotient;
        end

        // ---- Step 3a: restore original sign ----
        if (product < 0)
            scaled_value = -$signed({1'b0, rounded_magnitude});
        else
            scaled_value = $signed({1'b0, rounded_magnitude});

        // ---- Step 3b: optional ReLU ----
        if (apply_relu && scaled_value < 0)
            scaled_value = 65'sd0;

        // ---- Step 4: saturate to signed INT8 ----
        if (scaled_value > 65'sd127)
            output_data = 8'sd127;
        else if (scaled_value < -65'sd128)
            output_data = -8'sd128;
        else
            output_data = scaled_value[`DATA_WIDTH-1:0];
    end
        
        
    
endmodule
