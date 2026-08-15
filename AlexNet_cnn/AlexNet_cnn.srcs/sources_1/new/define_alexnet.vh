`ifndef DEFINE_ALEXNET_V
`define DEFINE_ALEXNET_V

// ==============================
// Define Memory Address Widths
//===============================
`define ACTIVATION_ADDR_WIDTH 13   
`define WEIGHT_ADDR_WIDTH 14
`define BIAS_ADDR_WIDTH 6

// =================
// Define Widths
// =================
`define DATA_WIDTH 8
`define WEIGHT_WIDTH 8
`define BIAS_WIDTH 32
`define ACC_WIDTH 32

// ==============================
// Define Loop-counter widths
// ==============================
`define ROW_COL_WIDTH     6   
`define CHANNEL_WIDTH     6   
`define KERNEL_WIDTH      3
`define FC_INPUT_INDEX_WIDTH  8
// ==============================
// Define Requantization widths
// ==============================
`define REQUANT_MULT_WIDTH   32   
`define REQUANT_SHIFT_WIDTH  6  
`define REQUANT_SHIFT_VALUE  24

// ==============================
// Define loop-controller states (Conv and Pool loop)
// ==============================
`define LOOP_STATE_WIDTH   2

`define LOOP_IDLE          2'd0
`define LOOP_REQUEST       2'd1
`define LOOP_WAIT_RESULT   2'd2
`define LOOP_DONE          2'd3

// ==============================
// Define network controller states
// CONV1 -> POOL1 -> CONV2 -> POOL2 ->
// CONV3 -> CONV4 -> CONV5 -> POOL5 ->
// FC6 -> FC7 -> FC8
// ==============================
`define NET_STATE_WIDTH    4

`define NET_IDLE           4'd0
`define NET_CONV1          4'd1
`define NET_POOL1          4'd2
`define NET_CONV2          4'd3
`define NET_POOL2          4'd4
`define NET_CONV3          4'd5
`define NET_CONV4          4'd6
`define NET_CONV5          4'd7
`define NET_POOL5          4'd8
`define NET_FC6            4'd9
`define NET_FC7            4'd10
`define NET_FC8            4'd11
`define NET_DONE           4'd12

`endif