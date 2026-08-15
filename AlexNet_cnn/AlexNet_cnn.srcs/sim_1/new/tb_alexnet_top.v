`timescale 1ns / 1ps
`include "define_alexnet.vh"

module tb_alexnet_top;

    localparam EXPECTED_CLASS = 32'd4;

    localparam MAX_CYCLES = 32'd20_000_000;

    reg clk;
    reg rst_n;
    reg start;

    wire busy;
    wire network_done;

    wire                          final_output_valid;
    wire signed [`DATA_WIDTH-1:0] final_output_data;
    wire [`CHANNEL_WIDTH-1:0]     final_output_index;

    wire [`NET_STATE_WIDTH-1:0] current_state;

    wire                          prediction_valid;
    wire [`CHANNEL_WIDTH-1:0]     predicted_class;
    wire signed [`DATA_WIDTH-1:0] maximum_logit;

    reg signed [`DATA_WIDTH-1:0] captured_logits [0:9];
    reg signed [`DATA_WIDTH-1:0] expected_logits  [0:9];

    reg [9:0] logit_received;

    reg                       prediction_received;
    reg [`CHANNEL_WIDTH-1:0]  captured_predicted_class;
    reg signed [`DATA_WIDTH-1:0] captured_maximum_logit;

    integer error_count;
    integer cycle_count;
    integer i;

    function [8*11-1:0] class_name;
        input [`CHANNEL_WIDTH-1:0] class_index;
        begin
            case (class_index)
                0: class_name = "airplane";
                1: class_name = "automobile";
                2: class_name = "bird";
                3: class_name = "cat";
                4: class_name = "deer";
                5: class_name = "dog";
                6: class_name = "frog";
                7: class_name = "horse";
                8: class_name = "ship";
                9: class_name = "truck";
                default: class_name = "unknown";
            endcase
        end
    endfunction

    // ============================================================
    // DUT
    // ============================================================
    alexnet_top dut (
        .clk   (clk),
        .rst_n (rst_n),
        .start (start),

        .busy         (busy),
        .network_done (network_done),

        .final_output_valid (final_output_valid),
        .final_output_data  (final_output_data),
        .final_output_index (final_output_index),

        .current_state (current_state),

        .prediction_valid (prediction_valid),
        .predicted_class  (predicted_class),
        .maximum_logit    (maximum_logit)
    );

    // ============================================================
    // Clock: 10 ns period
    // ============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // Load the golden FC8 logits for the current test image
    // ============================================================
    initial begin
        for (i = 0; i < 10; i = i + 1)
            expected_logits[i] = 0;

        $display("Loading expected logits: expected_logits_deer.mem");
        $readmemh("expected_logits_deer.mem", expected_logits);
    end

    // ============================================================
    // Capture FC8 outputs as they stream out
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            logit_received <= 10'b00000;

            for (i = 0; i < 10; i = i + 1)
                captured_logits[i] <= 0;
        end
        else begin
            if (final_output_valid && final_output_index < 10) begin
                captured_logits[final_output_index] <= final_output_data;
                logit_received[final_output_index]  <= 1'b1;

                $display(
                    "[cycle %0d] logit[%0d] = %0d",
                    cycle_count, final_output_index, final_output_data
                );
            end
        end
    end

    // ============================================================
    // Capture the one-cycle argmax result
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prediction_received      <= 1'b0;
            captured_predicted_class <= 0;
            captured_maximum_logit   <= 0;
        end
        else begin
            if (prediction_valid) begin
                prediction_received      <= 1'b1;
                captured_predicted_class <= predicted_class;
                captured_maximum_logit   <= maximum_logit;

                $display(
                    "[cycle %0d] prediction=%0d (%s) max=%0d",
                    cycle_count, predicted_class,
                    class_name(predicted_class), maximum_logit
                );
            end
        end
    end

    // ============================================================
    // Per-logit check task
    // ============================================================
    task check_logit;
        input integer index;
        begin
            if (!logit_received[index]) begin
                $display("FAIL: Logit[%0d] (%s) was not received.",
                    index, class_name(index[`CHANNEL_WIDTH-1:0]));
                error_count = error_count + 1;
            end
            else if (captured_logits[index] !== expected_logits[index]) begin
                $display("FAIL: Logit[%0d] (%s) expected %0d, actual %0d.",
                    index, class_name(index[`CHANNEL_WIDTH-1:0]),
                    expected_logits[index], captured_logits[index]);
                error_count = error_count + 1;
            end
            else begin
                $display("PASS: Logit[%0d] (%s) = %0d.",
                    index, class_name(index[`CHANNEL_WIDTH-1:0]),
                    captured_logits[index]);
            end
        end
    endtask

    // ============================================================
    // Main test sequence
    // ============================================================
    initial begin
        rst_n       = 1'b0;
        start       = 1'b0;
        error_count = 0;
        cycle_count = 0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("");
        $display("========================================");
        $display("Starting CIFAR AlexNet classification");
        $display("Expected class = %0d (%s)",
            EXPECTED_CLASS, class_name(EXPECTED_CLASS[`CHANNEL_WIDTH-1:0]));
        $display("========================================");

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        while (!prediction_received && cycle_count < MAX_CYCLES) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        @(posedge clk);
        #1;

        $display("");
        $display("========================================");
        $display("CIFAR AlexNet classification result");
        $display("========================================");

        if (cycle_count >= MAX_CYCLES) begin
            $display("FAIL: Timed out after %0d cycles.", MAX_CYCLES);
            error_count = error_count + 1;
        end
        else begin
            check_logit(0);
            check_logit(1);
            check_logit(2);
            check_logit(3);
            check_logit(4);
            check_logit(5);
            check_logit(6);
            check_logit(7);
            check_logit(8);
            check_logit(9);

            if (logit_received !== {10{1'b1}}) begin
                $display("FAIL: Missing logits. Mask=%b", logit_received);
                error_count = error_count + 1;
            end

            if (!prediction_received) begin
                $display("FAIL: No argmax prediction received.");
                error_count = error_count + 1;
            end
            else if (captured_predicted_class !== EXPECTED_CLASS[`CHANNEL_WIDTH-1:0]) begin
                $display("FAIL: Expected class %0d (%s), actual %0d (%s).",
                    EXPECTED_CLASS, class_name(EXPECTED_CLASS[`CHANNEL_WIDTH-1:0]),
                    captured_predicted_class, class_name(captured_predicted_class));
                error_count = error_count + 1;
            end
            else begin
                $display("PASS: Predicted class = %0d (%s).",
                    captured_predicted_class, class_name(captured_predicted_class));
            end

            if (captured_maximum_logit !== expected_logits[EXPECTED_CLASS[`CHANNEL_WIDTH-1:0]]) begin
                $display("FAIL: Maximum logit expected %0d, actual %0d.",
                    expected_logits[EXPECTED_CLASS[`CHANNEL_WIDTH-1:0]],
                    captured_maximum_logit);
                error_count = error_count + 1;
            end
            else begin
                $display("PASS: Maximum logit = %0d.", captured_maximum_logit);
            end
        end

        $display("----------------------------------------");

        if (error_count == 0) begin
            $display("RESULT: CIFAR AlexNet test PASSED.");
        end
        else begin
            $display("RESULT: CIFAR AlexNet test FAILED with %0d error(s).", error_count);
        end

        $display("========================================");
        $display("");

        $finish;
    end

endmodule