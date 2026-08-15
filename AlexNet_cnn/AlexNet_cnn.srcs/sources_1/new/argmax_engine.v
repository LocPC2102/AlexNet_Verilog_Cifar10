`timescale 1ns / 1ps
`include "define_alexnet.vh"

module argmax_engine (
    input wire clk,
    input wire rst_n,

    // Begin a new classification
    input wire start,

    // Stream of FC8 logits
    input wire                          input_valid,
    input wire [`CHANNEL_WIDTH-1:0]     input_index,
    input wire signed [`DATA_WIDTH-1:0] input_data,

    // Asserted when the final logit has been supplied
    input wire input_done,

    output reg busy,

    output reg prediction_valid,
    output reg [`CHANNEL_WIDTH-1:0] predicted_class,
    output reg signed [`DATA_WIDTH-1:0] maximum_logit
);

    reg has_value;

    reg signed [`DATA_WIDTH-1:0] current_maximum;
    reg [`CHANNEL_WIDTH-1:0]     current_class;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy             <= 1'b0;
            prediction_valid <= 1'b0;

            predicted_class <= 0;
            maximum_logit   <= {`DATA_WIDTH{1'b0}};

            has_value        <= 1'b0;
            current_maximum  <= {`DATA_WIDTH{1'b0}};
            current_class    <= 0;
        end
        else begin
            prediction_valid <= 1'b0;

            // Start a fresh argmax operation
            if (start) begin
                busy             <= 1'b1;
                has_value        <= 1'b0;
                current_maximum  <= {`DATA_WIDTH{1'b0}};
                current_class    <= 0;
            end

            // Accept one valid logit
            if (busy && input_valid) begin
                if (!has_value || input_data > current_maximum) begin
                    current_maximum <= input_data;
                    current_class   <= input_index;
                end

                has_value <= 1'b1;
            end

            // Publish the final prediction
            if (busy && input_done) begin
                busy <= 1'b0;

                if (input_valid) begin
                    // input_done may arrive on the same cycle as the
                    // final valid logit. Compare that value directly
                    // because nonblocking assignments have not yet
                    // updated current_maximum/current_class.
                    if (!has_value || input_data > current_maximum) begin
                        maximum_logit   <= input_data;
                        predicted_class <= input_index;
                    end
                    else begin
                        maximum_logit   <= current_maximum;
                        predicted_class <= current_class;
                    end

                    prediction_valid <= 1'b1;
                end
                else if (has_value) begin
                    maximum_logit   <= current_maximum;
                    predicted_class <= current_class;

                    prediction_valid <= 1'b1;
                end
            end
        end
    end

endmodule