`timescale 1ns / 1ps
`include "define_alexnet.vh"

module conv_controller #(
    parameter OUTPUT_HEIGHT   = 3,
    parameter OUTPUT_WIDTH    = 3,
    parameter OUTPUT_FILTERS  = 2,
    parameter INPUT_CHANNELS  = 3,
    parameter KERNEL_SIZE     = 3
)(
    input wire clk,
    input wire rst_n,

    // Begin processing one full convolution layer
    input wire start,

    // Datapath can accept the current activation/weight pair
    input wire operation_ready,

    // Datapath has produced one completed output value
    input wire result_valid,

    // One MAC operation is being presented this cycle
    output reg operation_valid,

    // Current loop indices
    output reg [`ROW_COL_WIDTH-1:0] output_row,
    output reg [`ROW_COL_WIDTH-1:0] output_col,
    output reg [`CHANNEL_WIDTH-1:0] output_filter,
    output reg [`CHANNEL_WIDTH-1:0] input_channel,
    output reg [`KERNEL_WIDTH-1:0]  kernel_row,
    output reg [`KERNEL_WIDTH-1:0]  kernel_col,

    // Accumulator control
    output reg first_operation,
    output reg last_operation,

    // Status
    output reg busy,
    output reg output_value_done,
    output reg layer_done
);

    reg [`LOOP_STATE_WIDTH-1:0] current_state;
    reg [`LOOP_STATE_WIDTH-1:0] next_state;

    reg [`ROW_COL_WIDTH-1:0] current_output_row;
    reg [`ROW_COL_WIDTH-1:0] next_output_row;

    reg [`ROW_COL_WIDTH-1:0] current_output_col;
    reg [`ROW_COL_WIDTH-1:0] next_output_col;

    reg [`CHANNEL_WIDTH-1:0] current_output_filter;
    reg [`CHANNEL_WIDTH-1:0] next_output_filter;

    reg [`CHANNEL_WIDTH-1:0] current_input_channel;
    reg [`CHANNEL_WIDTH-1:0] next_input_channel;

    reg [`KERNEL_WIDTH-1:0] current_kernel_row;
    reg [`KERNEL_WIDTH-1:0] next_kernel_row;

    reg [`KERNEL_WIDTH-1:0] current_kernel_col;
    reg [`KERNEL_WIDTH-1:0] next_kernel_col;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= `LOOP_IDLE;

            current_output_row    <= 0;
            current_output_col    <= 0;
            current_output_filter <= 0;
            current_input_channel <= 0;
            current_kernel_row    <= 0;
            current_kernel_col    <= 0;
        end
        else begin
            current_state <= next_state;

            current_output_row    <= next_output_row;
            current_output_col    <= next_output_col;
            current_output_filter <= next_output_filter;
            current_input_channel <= next_input_channel;
            current_kernel_row    <= next_kernel_row;
            current_kernel_col    <= next_kernel_col;
        end
    end
    
    // ============================================================
    // Combinational next-state and counter logic
    // ============================================================
    always @(*) begin
    // Default: hold current values unless a state says otherwise
        next_state = current_state;

        next_output_row    = current_output_row;
        next_output_col    = current_output_col;
        next_output_filter = current_output_filter;
        next_input_channel = current_input_channel;
        next_kernel_row    = current_kernel_row;
        next_kernel_col    = current_kernel_col;

        case (current_state)

            `LOOP_IDLE: begin
                next_output_row    = 0;
                next_output_col    = 0;
                next_output_filter = 0;
                next_input_channel = 0;
                next_kernel_row    = 0;
                next_kernel_col    = 0;

                if (start)
                    next_state = `LOOP_REQUEST;
            end

            
            `LOOP_REQUEST: begin
                if (operation_ready) begin

                    // Move to the next kernel column
                    if (current_kernel_col < KERNEL_SIZE - 1) begin
                        next_kernel_col = current_kernel_col + 1'b1;
                    end

                    // End of kernel row: reset column, advance row
                    else begin
                        next_kernel_col = 0;

                        if (current_kernel_row < KERNEL_SIZE - 1) begin
                            next_kernel_row = current_kernel_row + 1'b1;
                        end

                        // End of full kernel for this input channel:
                        // reset kernel row, advance input channel
                        else begin
                            next_kernel_row = 0;

                            if (current_input_channel < INPUT_CHANNELS - 1) begin
                                next_input_channel = current_input_channel + 1'b1;
                            end

                            // Final input channel AND final kernel
                            // position -> this output value is done
                            // accumulating; wait for the datapath
                            // to finish it.
                            else begin
                                next_input_channel = 0;
                                next_state = `LOOP_WAIT_RESULT;
                            end
                        end
                    end
                end
            end
            
            
            `LOOP_WAIT_RESULT: begin
                if (result_valid) begin

                    // Move to the next output filter at the same
                    // spatial location (row, col unchanged)
                    if (current_output_filter < OUTPUT_FILTERS - 1) begin
                        next_output_filter = current_output_filter + 1'b1;
                        next_state = `LOOP_REQUEST;
                    end

                    // All filters done for this location: reset
                    // filter, move horizontally to the next column
                    else begin
                        next_output_filter = 0;

                        if (current_output_col < OUTPUT_WIDTH - 1) begin
                            next_output_col = current_output_col + 1'b1;
                            next_state = `LOOP_REQUEST;
                        end

                        // End of row: reset column, move down a row
                        else begin
                            next_output_col = 0;

                            if (current_output_row < OUTPUT_HEIGHT - 1) begin
                                next_output_row = current_output_row + 1'b1;
                                next_state = `LOOP_REQUEST;
                            end

                            // Final row, final column, final filter
                            // -> the entire layer is done
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
                next_state = `LOOP_IDLE;

                next_output_row    = 0;
                next_output_col    = 0;
                next_output_filter = 0;
                next_input_channel = 0;
                next_kernel_row    = 0;
                next_kernel_col    = 0;
            end

        endcase
    end
    
    
    // ===============
    // Output logic
    // ===============
    always @(*) begin
        operation_valid = 1'b0;
        first_operation = 1'b0;
        last_operation  = 1'b0;

        busy               = 1'b0;
        output_value_done  = 1'b0;
        layer_done         = 1'b0;

        output_row     = current_output_row;
        output_col     = current_output_col;
        output_filter  = current_output_filter;
        input_channel  = current_input_channel;
        kernel_row     = current_kernel_row;
        kernel_col     = current_kernel_col;

        case (current_state)

            `LOOP_IDLE: begin
                busy = 1'b0;
            end

            `LOOP_REQUEST: begin
                busy            = 1'b1;
                operation_valid = 1'b1;

                // The accumulator must be reset on the very first
                // MAC of a new output value
                if (current_input_channel == 0 &&
                    current_kernel_row    == 0 &&
                    current_kernel_col    == 0) begin
                    first_operation = 1'b1;
                end

                // This is the final MAC contributing to the
                // current output value
                if (current_input_channel == INPUT_CHANNELS - 1 &&
                    current_kernel_row    == KERNEL_SIZE - 1 &&
                    current_kernel_col    == KERNEL_SIZE - 1) begin
                    last_operation = 1'b1;
                end
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
