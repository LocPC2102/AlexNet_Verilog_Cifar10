`timescale 1ns / 1ps
`include "define_alexnet.vh"

module network_controller (
    input wire clk,
    input wire rst_n,
    input wire start,

    // Layer completion inputs
    input wire conv1_done,
    input wire pool1_done,
    input wire conv2_done,
    input wire pool2_done,
    input wire conv3_done,
    input wire conv4_done,
    input wire conv5_done,
    input wire pool5_done,
    input wire fc6_done,
    input wire fc7_done,
    input wire fc8_done,

    // One-cycle layer start pulses
    output reg conv1_start,
    output reg pool1_start,
    output reg conv2_start,
    output reg pool2_start,
    output reg conv3_start,
    output reg conv4_start,
    output reg conv5_start,
    output reg pool5_start,
    output reg fc6_start,
    output reg fc7_start,
    output reg fc8_start,

    output wire busy,
    output reg network_done,

    output reg [`NET_STATE_WIDTH-1:0] current_state
);

    assign busy =
        current_state != `NET_IDLE &&
        current_state != `NET_DONE;

    // ============================================================
    // Sequential controller
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= `NET_IDLE;

            conv1_start <= 1'b0;
            pool1_start <= 1'b0;
            conv2_start <= 1'b0;
            pool2_start <= 1'b0;
            conv3_start <= 1'b0;
            conv4_start <= 1'b0;
            conv5_start <= 1'b0;
            pool5_start <= 1'b0;
            fc6_start   <= 1'b0;
            fc7_start   <= 1'b0;
            fc8_start   <= 1'b0;

            network_done <= 1'b0;
        end
        else begin
            // All start signals default to a one-clock pulse
            conv1_start <= 1'b0;
            pool1_start <= 1'b0;
            conv2_start <= 1'b0;
            pool2_start <= 1'b0;
            conv3_start <= 1'b0;
            conv4_start <= 1'b0;
            conv5_start <= 1'b0;
            pool5_start <= 1'b0;
            fc6_start   <= 1'b0;
            fc7_start   <= 1'b0;
            fc8_start   <= 1'b0;

            network_done <= 1'b0;

            case (current_state)

                `NET_IDLE: begin
                    if (start) begin
                        conv1_start   <= 1'b1;
                        current_state <= `NET_CONV1;
                    end
                end

                `NET_CONV1: begin
                    if (conv1_done) begin
                        pool1_start   <= 1'b1;
                        current_state <= `NET_POOL1;
                    end
                end

                `NET_POOL1: begin
                    if (pool1_done) begin
                        conv2_start   <= 1'b1;
                        current_state <= `NET_CONV2;
                    end
                end

                `NET_CONV2: begin
                    if (conv2_done) begin
                        pool2_start   <= 1'b1;
                        current_state <= `NET_POOL2;
                    end
                end

                `NET_POOL2: begin
                    if (pool2_done) begin
                        conv3_start   <= 1'b1;
                        current_state <= `NET_CONV3;
                    end
                end

                `NET_CONV3: begin
                    if (conv3_done) begin
                        conv4_start   <= 1'b1;
                        current_state <= `NET_CONV4;
                    end
                end

                `NET_CONV4: begin
                    if (conv4_done) begin
                        conv5_start   <= 1'b1;
                        current_state <= `NET_CONV5;
                    end
                end

                `NET_CONV5: begin
                    if (conv5_done) begin
                        pool5_start   <= 1'b1;
                        current_state <= `NET_POOL5;
                    end
                end

                `NET_POOL5: begin
                    if (pool5_done) begin
                        fc6_start     <= 1'b1;
                        current_state <= `NET_FC6;
                    end
                end

                `NET_FC6: begin
                    if (fc6_done) begin
                        fc7_start     <= 1'b1;
                        current_state <= `NET_FC7;
                    end
                end

                `NET_FC7: begin
                    if (fc7_done) begin
                        fc8_start     <= 1'b1;
                        current_state <= `NET_FC8;
                    end
                end

                `NET_FC8: begin
                    if (fc8_done) begin
                        current_state <= `NET_DONE;
                    end
                end

                `NET_DONE: begin
                    network_done  <= 1'b1;
                    current_state <= `NET_IDLE;
                end

                default: begin
                    current_state <= `NET_IDLE;
                end

            endcase
        end
    end

endmodule