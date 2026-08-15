`timescale 1ns / 1ps
`include "define_alexnet.vh"

module activation_buffer #(
    parameter DEPTH = 1024
)(
    input wire clk,

    input wire write_enable,
    input wire [`ACTIVATION_ADDR_WIDTH-1:0] write_address,
    input wire [`DATA_WIDTH-1:0]            write_data,

    input  wire [`ACTIVATION_ADDR_WIDTH-1:0] read_address,
    output reg  [`DATA_WIDTH-1:0]             read_data
);

    // Hint to the synthesizer to map this onto Block RAM
    (* ram_style = "block" *)
    reg signed [`DATA_WIDTH-1:0] memory [0:DEPTH-1];

    always @(posedge clk) begin
        if (write_enable) begin
            if (write_address < DEPTH)
                memory[write_address] <= write_data;
        end

        if (read_address < DEPTH)
            read_data <= memory[read_address];
        else
            read_data <= 0;
    end

    // ---- Simulation-only bound checking (not synthesized) ----
    `ifndef SYNTHESIS
        always @(posedge clk) begin
            if (write_enable && write_address >= DEPTH) begin
                $display(
                    "ERROR: activation_buffer write address %0d exceeds depth %0d",
                    write_address, DEPTH
                );
            end

            if (read_address >= DEPTH) begin
                $display(
                    "ERROR: activation_buffer read address %0d exceeds depth %0d",
                    read_address, DEPTH
                );
            end
        end
    `endif

endmodule
