`timescale 1ns / 1ps
`include "define_alexnet.vh"

module pool_engine #(
    parameter INPUT_HEIGHT  = 4,
    parameter INPUT_WIDTH   = 4,
    parameter CHANNELS      = 1,

    parameter OUTPUT_HEIGHT = 2,
    parameter OUTPUT_WIDTH  = 2,

    parameter POOL_SIZE     = 2,
    parameter STRIDE        = 2
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    output wire [`ACTIVATION_ADDR_WIDTH-1:0] external_read_address,
    input  wire signed [`DATA_WIDTH-1:0]     external_read_data,

    output wire busy,
    output wire layer_done,

    output reg                          output_valid,
    output reg signed [`DATA_WIDTH-1:0] output_data,

    output reg [`ROW_COL_WIDTH-1:0] output_row_index,
    output reg [`ROW_COL_WIDTH-1:0] output_col_index,
    output reg [`CHANNEL_WIDTH-1:0] output_channel_index,

    output reg [`ACTIVATION_ADDR_WIDTH-1:0] output_address
);

    // ============================================================
    // Loop-controller signals
    // ============================================================
    wire element_valid;
    wire element_ready;

    wire [`ROW_COL_WIDTH-1:0] loop_output_row;
    wire [`ROW_COL_WIDTH-1:0] loop_output_col;
    wire [`CHANNEL_WIDTH-1:0] loop_output_channel;

    wire [`ROW_COL_WIDTH-1:0] loop_pool_row;
    wire [`ROW_COL_WIDTH-1:0] loop_pool_col;

    wire first_element;
    wire last_element;

    wire pool_result_valid;
    wire signed [`DATA_WIDTH-1:0] pool_result;

    pool_controller #(
        .OUTPUT_HEIGHT (OUTPUT_HEIGHT),
        .OUTPUT_WIDTH  (OUTPUT_WIDTH),
        .CHANNELS      (CHANNELS),
        .POOL_SIZE     (POOL_SIZE)
    ) loop_ctrl_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),

        .element_ready  (element_ready),
        .result_valid   (pool_result_valid),

        .element_valid  (element_valid),

        .output_row     (loop_output_row),
        .output_col     (loop_output_col),
        .output_channel (loop_output_channel),

        .pool_row       (loop_pool_row),
        .pool_col       (loop_pool_col),

        .first_element  (first_element),
        .last_element   (last_element),

        .busy               (busy),
        .output_value_done  (),
        .layer_done         (layer_done)
    );

    // ============================================================
    // Address generator
    // ============================================================
    wire [`ACTIVATION_ADDR_WIDTH-1:0] activation_address;
    wire [`ROW_COL_WIDTH-1:0] unused_input_row;
    wire [`ROW_COL_WIDTH-1:0] unused_input_col;

    pool_address_generator #(
        .INPUT_HEIGHT (INPUT_HEIGHT),
        .INPUT_WIDTH  (INPUT_WIDTH),
        .STRIDE       (STRIDE)
    ) addr_gen_inst (
        .output_row     (loop_output_row),
        .output_col     (loop_output_col),
        .output_channel (loop_output_channel),

        .pool_row       (loop_pool_row),
        .pool_col       (loop_pool_col),

        .activation_address (activation_address),

        .input_row (unused_input_row),
        .input_col (unused_input_col)
    );

    assign external_read_address = activation_address;

    // ============================================================
    // Delay pipeline: the buffer read has 1-cycle latency, so the
    // control flags describing THIS data must be delayed to match
    // ============================================================
    reg element_valid_d;
    reg first_element_d;
    reg last_element_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            element_valid_d <= 1'b0;
            first_element_d <= 1'b0;
            last_element_d  <= 1'b0;
        end
        else begin
            element_valid_d <= element_valid;
            first_element_d <= element_valid && first_element;
            last_element_d  <= element_valid && last_element;
        end
    end

    // ============================================================
    // Comparator datapath
    // ============================================================
    pool_datapath datapath_inst (
        .clk            (clk),
        .rst_n          (rst_n),

        .element_valid  (element_valid_d),
        .first_element  (first_element_d),
        .last_element   (last_element_d),

        .activation_in  (external_read_data),

        .element_ready  (element_ready),

        .result_valid   (pool_result_valid),
        .result_out     (pool_result),

        .debug_current_max ()
    );

    // ============================================================
    // Remember which output value is being computed, captured at
    // the moment the loop controller accepts its last read
    // ============================================================
    reg [`ROW_COL_WIDTH-1:0] pending_output_row;
    reg [`ROW_COL_WIDTH-1:0] pending_output_col;
    reg [`CHANNEL_WIDTH-1:0] pending_output_channel;
    reg [`ACTIVATION_ADDR_WIDTH-1:0] pending_output_address;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_output_row     <= 0;
            pending_output_col     <= 0;
            pending_output_channel <= 0;
            pending_output_address <= 0;
        end
        else if (element_valid && element_ready && last_element) begin
            pending_output_row     <= loop_output_row;
            pending_output_col     <= loop_output_col;
            pending_output_channel <= loop_output_channel;

            pending_output_address <=
                loop_output_channel * OUTPUT_HEIGHT * OUTPUT_WIDTH
                + loop_output_row * OUTPUT_WIDTH
                + loop_output_col;
        end
    end

    // ============================================================
    // Publish the completed pooled result
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_valid          <= 1'b0;
            output_data           <= {`DATA_WIDTH{1'b0}};
            output_row_index      <= 0;
            output_col_index      <= 0;
            output_channel_index  <= 0;
            output_address        <= 0;
        end
        else begin
            output_valid <= 1'b0;

            if (pool_result_valid) begin
                output_valid <= 1'b1;
                output_data  <= pool_result;

                output_row_index     <= pending_output_row;
                output_col_index     <= pending_output_col;
                output_channel_index <= pending_output_channel;
                output_address       <= pending_output_address;
            end
        end
    end

endmodule