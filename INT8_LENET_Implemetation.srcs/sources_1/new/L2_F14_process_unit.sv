`timescale 1ns / 1ps

module L2_F14_process_unit #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10,
    parameter CONV_KERNEL_WIDTH = 3,
    parameter CONV_KERNEL_HEIGHT = 3,
    parameter CONV_FM_WIDTH = 13,
    parameter CONV_FM_HEIGHT = 13,
    parameter CONV_RESULT_WIDTH = 11,
    parameter CONV_RESULT_HEIGHT = 11,
    parameter POOL_KERNEL_WIDTH = 2,
    parameter POOL_KERNEL_HEIGHT = 2,
    parameter LAYER_OUTPUT_WIDTH = 5,
    parameter LAYER_OUTPUT_HEIGHT = 5,
    parameter CHANNEL_NUM = 6,
	parameter M0_WIDTH = 32
    )
(
    input logic clk, reset, run,
    input logic  [DATA_WIDTH-1:0] fm_data_in [6],
    input logic signed [DATA_WIDTH-1:0] weight_data_in [6],
    input logic [ADDR_WIDTH-1:0] result_read_addr,
    
    input logic is_last_fm_addr,
    output logic update_fm_begin_addr,
    output logic [ADDR_WIDTH-1:0] weight_read_addr,
    output logic fm_gen_addr_en,
    output logic  [DATA_WIDTH-1:0] result_out,
    output logic done
);

logic  [DATA_WIDTH-1:0] maxrelu_result;
logic [ADDR_WIDTH-1:0] maxrelu_wr_addr;
logic maxrelu_we;


FM_Process_Branch#(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(CONV_FM_WIDTH),
	.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH (M0_WIDTH)
	)process_unit_0(
	 .clk(clk), .run(run), .reset(reset),
	 .q_data_in(fm_data_in), .q_weight_in(weight_data_in),
	 .Z_data_in('d57), .Z_weight_in('d0), .Zo_in('d75), .M0_in('d1327363084),
	 .bias_in(-'d266), .n_in('d9),
	 .is_last_fm_addr(is_last_fm_addr), 
	 .update_fm_begin_addr(update_fm_begin_addr),
	 .fm_gen_addr_en(fm_gen_addr_en),
	 .wt_read_addr_out(weight_read_addr),
	 .maxrelu_result_out(maxrelu_result),
	 .wr_addr_out(maxrelu_wr_addr),
	 .wr_en_out(maxrelu_we),
	 .done(done)
	 //.conv_result(conv_result),
	 //.conv_we (conv_we)
	);


M10K #(
    .ITE_NUM(LAYER_OUTPUT_WIDTH*LAYER_OUTPUT_HEIGHT),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) op_buffer (
    .q            (result_out),
    .d            (maxrelu_result),
    .write_address(maxrelu_wr_addr),
    .read_address (result_read_addr),
    .we           (maxrelu_we),
    .clk          (clk)
);

endmodule
