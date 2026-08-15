`timescale 1ns / 1ps
`include "define_alexnet.vh"

module pool_controller #(
    parameter OUTPUT_HEIGHT = 2,
    parameter OUTPUT_WIDTH  = 2,
    parameter CHANNELS      = 2,
    parameter POOL_SIZE     = 2
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    // Pooling datapath can accept the current activation
    input wire element_ready,

    // Asserted after the max for one window is available
    input wire result_valid,

    // One activation request is valid this cycle
    output reg element_valid,

    // Current output coordinate
    output reg [`ROW_COL_WIDTH-1:0] output_row,
    output reg [`ROW_COL_WIDTH-1:0] output_col,
    output reg [`CHANNEL_WIDTH-1:0] output_channel,

    // Position inside the pooling window
    output reg [`ROW_COL_WIDTH-1:0] pool_row,
    output reg [`ROW_COL_WIDTH-1:0] pool_col,

    output reg first_element,
    output reg last_element,

    output reg busy,
    output reg output_value_done,
    output reg layer_done
);

    reg [`LOOP_STATE_WIDTH-1:0] current_state, next_state;

    reg [`ROW_COL_WIDTH-1:0] current_output_row, next_output_row;
    reg [`ROW_COL_WIDTH-1:0] current_output_col, next_output_col;
    reg [`CHANNEL_WIDTH-1:0] current_output_channel, next_output_channel;
    reg [`ROW_COL_WIDTH-1:0] current_pool_row, next_pool_row;
    reg [`ROW_COL_WIDTH-1:0] current_pool_col, next_pool_col;

    // ============================================================
    // Sequential state and counter registers
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= `LOOP_IDLE;

            current_output_row     <= 0;
            current_output_col     <= 0;
            current_output_channel <= 0;
            current_pool_row       <= 0;
            current_pool_col       <= 0;
        end
        else begin
            current_state <= next_state;

            current_output_row     <= next_output_row;
            current_output_col     <= next_output_col;
            current_output_channel <= next_output_channel;
            current_pool_row       <= next_pool_row;
            current_pool_col       <= next_pool_col;
        end
    end

    // ============================================================
    // Next-state and counter logic
    // ============================================================
    always @(*) begin
        next_state = current_state;

        next_output_row     = current_output_row;
        next_output_col     = current_output_col;
        next_output_channel = current_output_channel;
        next_pool_row       = current_pool_row;
        next_pool_col       = current_pool_col;

        case (current_state)

            `LOOP_IDLE: begin
                next_output_row     = 0;
                next_output_col     = 0;
                next_output_channel = 0;
                next_pool_row       = 0;
                next_pool_col       = 0;

                if (start)
                    next_state = `LOOP_REQUEST;
            end

            // Present one activation from the pooling window
            `LOOP_REQUEST: begin
                if (element_ready) begin
                    if (current_pool_col < POOL_SIZE - 1) begin
                        next_pool_col = current_pool_col + 1'b1;
                    end
                    else begin
                        next_pool_col = 0;

                        if (current_pool_row < POOL_SIZE - 1) begin
                            next_pool_row = current_pool_row + 1'b1;
                        end
                        else begin
                            // Full window requested
                            next_pool_row = 0;
                            next_state    = `LOOP_WAIT_RESULT;
                        end
                    end
                end
            end

            `LOOP_WAIT_RESULT: begin
                if (result_valid) begin

                    // Next channel at the same spatial position
                    if (current_output_channel < CHANNELS - 1) begin
                        next_output_channel = current_output_channel + 1'b1;
                        next_state          = `LOOP_REQUEST;
                    end
                    else begin
                        next_output_channel = 0;

                        // Move to the next output column
                        if (current_output_col < OUTPUT_WIDTH - 1) begin
                            next_output_col = current_output_col + 1'b1;
                            next_state      = `LOOP_REQUEST;
                        end
                        else begin
                            next_output_col = 0;

                            // Move to the next output row
                            if (current_output_row < OUTPUT_HEIGHT - 1) begin
                                next_output_row = current_output_row + 1'b1;
                                next_state      = `LOOP_REQUEST;
                            end
                            else begin
                                next_state = `LOOP_DONE;
                            end
                        end
                    end
                end
            end

            `LOOP_DONE: begin
                if (!start)
                    next_state = `LOOP_IDLE;
            end

            default: begin
                next_state           = `LOOP_IDLE;
                next_output_row      = 0;
                next_output_col      = 0;
                next_output_channel  = 0;
                next_pool_row        = 0;
                next_pool_col        = 0;
            end

        endcase
    end

    // ============================================================
    // Output logic
    // ============================================================
    always @(*) begin
        element_valid      = 1'b0;
        first_element      = 1'b0;
        last_element       = 1'b0;
        busy               = 1'b0;
        output_value_done  = 1'b0;
        layer_done         = 1'b0;

        output_row     = current_output_row;
        output_col     = current_output_col;
        output_channel = current_output_channel;
        pool_row       = current_pool_row;
        pool_col       = current_pool_col;

        case (current_state)

            `LOOP_IDLE: begin
                busy = 1'b0;
            end

            `LOOP_REQUEST: begin
                busy          = 1'b1;
                element_valid = 1'b1;

                if (current_pool_row == 0 && current_pool_col == 0)
                    first_element = 1'b1;

                if (current_pool_row == POOL_SIZE - 1 &&
                    current_pool_col == POOL_SIZE - 1)
                    last_element = 1'b1;
            end

            `LOOP_WAIT_RESULT: begin
                busy = 1'b1;

                if (result_valid)
                    output_value_done = 1'b1;
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