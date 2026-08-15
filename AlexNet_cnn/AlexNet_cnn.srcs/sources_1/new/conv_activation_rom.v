`timescale 1ns / 1ps
`include "define_alexnet.vh"

module conv_activation_rom #(
    parameter INPUT_HEIGHT   = 5,
    parameter INPUT_WIDTH    = 5,
    parameter INPUT_CHANNELS = 3,
    parameter ACTIVATION_FILE = ""
)(
    input wire clk,

    input wire [`ACTIVATION_ADDR_WIDTH-1:0] activation_address,
    input wire                              padding_active,

    output reg signed [`DATA_WIDTH-1:0] activation_out
);

    localparam TOTAL_ACTIVATIONS =
        INPUT_HEIGHT * INPUT_WIDTH * INPUT_CHANNELS;

    reg signed [`DATA_WIDTH-1:0]
        activation_memory [0:TOTAL_ACTIVATIONS-1];
        
    integer i;

    initial begin
        // Zero-initialize so simulation never reads 'x' before
        // the file (if any) is loaded
        for (i = 0; i < TOTAL_ACTIVATIONS; i = i + 1)
            activation_memory[i] = 0;

        if (ACTIVATION_FILE != "") begin
            $display("Loading activation file: %s", ACTIVATION_FILE);
            $readmemh(ACTIVATION_FILE, activation_memory);
        end
        else begin
            $display("No activation file supplied; using zeros.");
        end
    end

    // ============================================================
    // Synchronous read
    //
    // Returns zero when padding_active is set, or when the
    // address is somehow out of range (defensive bound check).
    // ============================================================
    always @(posedge clk) begin
        if (padding_active)
            activation_out <= {`DATA_WIDTH{1'b0}};
        else if (activation_address < TOTAL_ACTIVATIONS)
            activation_out <= activation_memory[activation_address];
        else
            activation_out <= {`DATA_WIDTH{1'b0}};
    end    
endmodule
