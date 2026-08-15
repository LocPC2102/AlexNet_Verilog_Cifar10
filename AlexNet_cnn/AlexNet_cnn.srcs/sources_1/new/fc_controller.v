`timescale 1ns / 1ps
`include "define_alexnet.vh"

module fc_controller #(
    parameter INPUT_SIZE     = 4,
    parameter OUTPUT_NEURONS = 3
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    input wire operation_ready,
    input wire result_valid,

    output reg operation_valid,

    output reg [`FC_INPUT_INDEX_WIDTH-1:0] input_index,
    output reg [`CHANNEL_WIDTH-1:0]         output_neuron,

    output reg first_operation,
    output reg last_operation,

    output reg busy,
    output reg layer_done
);

    reg [`LOOP_STATE_WIDTH-1:0] current_state, next_state;

    reg [`FC_INPUT_INDEX_WIDTH-1:0] current_input_index, next_input_index;
    reg [`CHANNEL_WIDTH-1:0]        current_output_neuron, next_output_neuron;

    // ============================================================
    // Sequential state and counter registers
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state          <= `LOOP_IDLE;
            current_input_index    <= 0;
            current_output_neuron  <= 0;
        end
        else begin
            current_state          <= next_state;
            current_input_index    <= next_input_index;
            current_output_neuron  <= next_output_neuron;
        end
    end

    // ============================================================
    // Next-state and counter logic
    // ============================================================
    always @(*) begin
        next_state         = current_state;
        next_input_index   = current_input_index;
        next_output_neuron = current_output_neuron;

        case (current_state)

            `LOOP_IDLE: begin
                next_input_index   = 0;
                next_output_neuron = 0;

                if (start)
                    next_state = `LOOP_REQUEST;
            end

            // Present one input/weight pair
            `LOOP_REQUEST: begin
                if (operation_ready) begin
                    if (current_input_index < INPUT_SIZE - 1) begin
                        next_input_index = current_input_index + 1'b1;
                    end
                    else begin
                        // All inputs for this neuron have been issued
                        next_input_index = 0;
                        next_state       = `LOOP_WAIT_RESULT;
                    end
                end
            end

            `LOOP_WAIT_RESULT: begin
                if (result_valid) begin
                    if (current_output_neuron < OUTPUT_NEURONS - 1) begin
                        next_output_neuron = current_output_neuron + 1'b1;
                        next_state         = `LOOP_REQUEST;
                    end
                    else begin
                        // All neurons done -> full layer done
                        next_state = `LOOP_DONE;
                    end
                end
            end

            `LOOP_DONE: begin
                if (!start)
                    next_state = `LOOP_IDLE;
            end

            default: begin
                next_state         = `LOOP_IDLE;
                next_input_index   = 0;
                next_output_neuron = 0;
            end

        endcase
    end

    // ============================================================
    // Output logic
    // ============================================================
    always @(*) begin
        operation_valid = 1'b0;
        first_operation = 1'b0;
        last_operation  = 1'b0;
        busy            = 1'b0;
        layer_done      = 1'b0;

        input_index    = current_input_index;
        output_neuron  = current_output_neuron;

        case (current_state)

            `LOOP_IDLE: begin
                busy = 1'b0;
            end

            `LOOP_REQUEST: begin
                busy            = 1'b1;
                operation_valid = 1'b1;

                if (current_input_index == 0)
                    first_operation = 1'b1;

                if (current_input_index == INPUT_SIZE - 1)
                    last_operation = 1'b1;
            end

            `LOOP_WAIT_RESULT: begin
                busy = 1'b1;
            end

            `LOOP_DONE: begin
                busy       = 1'b0;
                layer_done = 1'b1;
            end

            default: begin
                busy = 1'b0;
            end

        endcase
    end

endmodule