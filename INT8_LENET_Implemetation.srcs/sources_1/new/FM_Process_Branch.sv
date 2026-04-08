module FM_Process_Branch #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10,
    parameter CONV_KERNEL_WIDTH = 3,
    parameter CONV_KERNEL_HEIGHT = 3,
    parameter CONV_FM_WIDTH = 28,
    parameter CONV_FM_HEIGHT = 28,
    parameter CONV_RESULT_WIDTH = 26,
    parameter CONV_RESULT_HEIGHT = 26,
    parameter POOL_KERNEL_WIDTH = 2,
    parameter POOL_KERNEL_HEIGHT = 2,
    parameter CHANNEL_NUM = 6,
    parameter M0_WIDTH = 32
)(
 input logic clk, run, reset,
 input logic         [DATA_WIDTH-1: 0] q_data_in [CHANNEL_NUM], // unsigned
 input logic         [DATA_WIDTH-1: 0] Z_data_in,
 input logic signed [DATA_WIDTH-1: 0] q_weight_in[CHANNEL_NUM],
 input logic signed [DATA_WIDTH-1: 0] Z_weight_in,
 input logic         [DATA_WIDTH-1:0]  Zo_in,
 input logic signed [M0_WIDTH-1:0]    M0_in,
 input logic signed [31:0]            bias_in,
 input logic         [5:0]            n_in,

 input logic is_last_fm_addr,
 output logic update_fm_begin_addr,

 output logic fm_gen_addr_en,
 output logic [ADDR_WIDTH-1:0] wt_read_addr_out,
 output logic signed [DATA_WIDTH-1:0] maxrelu_result_out,
 output logic [ADDR_WIDTH-1:0] wr_addr_out,
 output logic wr_en_out,
 output logic done,

 // optional debug
 output logic signed [DATA_WIDTH-1:0] conv_result,
 output logic conv_we,
 output logic [ADDR_WIDTH-1:0] conv_waddr
);

logic [ADDR_WIDTH-1:0] conv_wr_addr_out;
logic conv_we_out;
logic conv_done;
logic signed [DATA_WIDTH-1:0] conv_result_out;
logic maxrelu_done;

assign conv_result = conv_result_out;
assign conv_we     = conv_we_out;
assign conv_waddr  = conv_wr_addr_out;
assign done        = maxrelu_done;

MAC_wrapper #(
    .KERNEL_WIDTH(CONV_KERNEL_WIDTH),
    .KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
    .FM_WIDTH(CONV_FM_WIDTH),
    .FM_HEIGHT(CONV_FM_HEIGHT),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .M0_WIDTH(M0_WIDTH),
    .CHANNEL_PAR(CHANNEL_NUM)
) MAC_unit (
    .clk(clk), .reset(reset), .run(run),
    .q_weight_in(q_weight_in), .q_data_in(q_data_in),
    .Z_weight_in(Z_weight_in), .Z_data_in(Z_data_in),
    .bias_in(bias_in),
    .M0_in(M0_in), .Zo_in(Zo_in), .n_in(n_in),
    .is_last_begin_addr(is_last_fm_addr),
    .update_data_addr_out(update_fm_begin_addr),
    .fm_gen_addr_en(fm_gen_addr_en),
    .wt_read_addr_out(wt_read_addr_out),
    .q_out(conv_result_out),
    .wr_addr_out(conv_wr_addr_out),
    .we_out(conv_we_out),
    .done(conv_done)
);

MaxPooling_Relu_stream #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .FM_WIDTH(CONV_RESULT_WIDTH),
    .FM_HEIGHT(CONV_RESULT_HEIGHT)
) MaxRelu_unit (
    .clk(clk),
    .reset(reset),
    .in_valid(conv_we_out),
    .data_in(conv_result_out),
    .Zo_in(Zo_in),
    .result_out(maxrelu_result_out),
    .w_address_out(wr_addr_out),
    .we_out(wr_en_out),
    .done(maxrelu_done)
);

endmodule
