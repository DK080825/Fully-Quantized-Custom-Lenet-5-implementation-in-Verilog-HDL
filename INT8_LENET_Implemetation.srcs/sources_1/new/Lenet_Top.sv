`timescale 1ns / 1ps

module Lenet_Top #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10,
    parameter POOL_KERNEL_WIDTH = 2,
    parameter POOL_KERNEL_HEIGHT = 2,
    parameter L1_CONV_KERNEL_WIDTH = 3,
    parameter L1_CONV_KERNEL_HEIGHT = 3,
    parameter L1_CONV_FM_WIDTH = 28,
    parameter L1_CONV_FM_HEIGHT = 28,
	
	parameter INPUT_BANK1_WIDTH = 28,
	parameter INPUT_BANK1_HEIGHT = 14,
	parameter INPUT_BANK2_WIDTH = 28,
	parameter INPUT_BANK2_HEIGHT = 16,
	parameter CONV_RESULT1_WIDTH = 26,
    parameter CONV_RESULT1_HEIGHT = 12,
	parameter CONV_RESULT2_WIDTH = 26,
    parameter CONV_RESULT2_HEIGHT = 14,
	parameter L1_OUTPUT1_WIDTH = 13,
    parameter L1_OUTPUT1_HEIGHT = 6,
	parameter L1_OUTPUT2_WIDTH = 13,
    parameter L1_OUTPUT2_HEIGHT = 7,
	
    parameter L1_CONV_RESULT_WIDTH = 26,
    parameter L1_CONV_RESULT_HEIGHT = 26,
    parameter L1_LAYER_OUTPUT_WIDTH = 13,
    parameter L1_LAYER_OUTPUT_HEIGHT = 13,
    parameter L2_CONV_KERNEL_WIDTH = 3,
    parameter L2_CONV_KERNEL_HEIGHT = 3,
    parameter L2_CONV_FM_WIDTH = 13,
    parameter L2_CONV_FM_HEIGHT = 13,
    parameter L2_CONV_RESULT_WIDTH = 11,
    parameter L2_CONV_RESULT_HEIGHT = 11,
    parameter L2_LAYER_OUTPUT_WIDTH = 5,
    parameter L2_LAYER_OUTPUT_HEIGHT = 5,
    
    parameter MLP_VEC_SIZE = 400,
	parameter M0_WIDTH = 32
)( 
input logic clk,
input logic start_in,
input logic reset_in,
input logic [ADDR_WIDTH-1:0] mnist_waddr,
input logic mnist_wren,
input logic signed [DATA_WIDTH-1:0] mnist_wdata,
output logic [3:0] classification, 
output logic done
   );
   
   
// Board Logistics instantiations

logic reset, reset_0;
always@(posedge clk) begin
	reset_0 <= reset_in;
	reset <= reset_0;
end

logic start, start_0;
always@(posedge clk) begin
	if (reset) start <= 'b0;
	else begin
		if (start == 0)
			start <= start_in;
		else	
			start <= start;
	end
end
always@(posedge clk) begin
	if (reset) start_0 <= 'b0;
	else begin
		if (start_0 == 0)
			start_0 <= start;
		else	
			start_0 <= start_0;
	end
end

logic run;
assign run = !start_0 && start;
 

// Board Logistics Ends
logic we_a, we_b;
logic [ADDR_WIDTH-1:0] waddr_a, waddr_b; 
logic [ADDR_WIDTH-1:0] input_mem_read_addr0, input_mem_read_addr1;
logic signed [DATA_WIDTH-1:0] input_data_in0[1];
logic signed [DATA_WIDTH-1:0] input_data_in1[1];
logic signed [DATA_WIDTH-1:0] l1_output [12];
logic  [ADDR_WIDTH-1:0] l1_read_addr;
logic  [ADDR_WIDTH-1:0] l2_read_addr;
logic signed [DATA_WIDTH-1:0] l2_data_in [6];
logic signed [DATA_WIDTH-1:0] l2_output [16];

logic [ADDR_WIDTH-1:0] mlp_read_addr;
logic signed [DATA_WIDTH-1:0] mlp_data_in [16];
logic l1_done,l2_done;



input_bank_ctrl #(
	.ADDR_WIDTH(ADDR_WIDTH),
	.INPUT_WIDTH(L1_CONV_FM_WIDTH), 
	.INPUT_HEIGHT(L1_CONV_FM_HEIGHT)
) bank_ctrl (
	.mnist_wren(mnist_wren),
	.mnist_waddr(mnist_waddr),
	.we_a(we_a), .we_b(we_b),
	.waddr_a(waddr_a), .waddr_b(waddr_b)
);


M10K #(
	.ITE_NUM(INPUT_BANK1_WIDTH*INPUT_BANK1_HEIGHT),
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH)
) input_bank1 (
	.q            (input_data_in0[0]),
	.d            (mnist_wdata),
	.write_address(waddr_a),
	.read_address (input_mem_read_addr0),
	.we           (we_a),
	.clk          (clk)
);

M10K #(
	.ITE_NUM(INPUT_BANK2_WIDTH*INPUT_BANK2_HEIGHT),
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH)
) input_bank2 (
	.q            (input_data_in1[0]),
	.d            (mnist_wdata),
	.write_address(waddr_b),
	.read_address (input_mem_read_addr1),
	.we           (we_b),
	.clk          (clk)
);


//      LAYER 1

Layer1_Wrapper #(
.DATA_WIDTH(DATA_WIDTH),
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(L1_CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(L1_CONV_KERNEL_HEIGHT),
.IMAGE_BANK1_WIDTH(INPUT_BANK1_WIDTH),
.IMAGE_BANK1_HEIGHT(INPUT_BANK1_HEIGHT),
.IMAGE_BANK2_WIDTH(INPUT_BANK2_WIDTH),
.IMAGE_BANK2_HEIGHT(INPUT_BANK2_HEIGHT),
.CONV_RESULT1_WIDTH(CONV_RESULT1_WIDTH),
.CONV_RESULT1_HEIGHT(CONV_RESULT1_HEIGHT),
.CONV_RESULT2_WIDTH(CONV_RESULT2_WIDTH),
.CONV_RESULT2_HEIGHT(CONV_RESULT2_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT1_WIDTH(L1_OUTPUT1_WIDTH),
.LAYER_OUTPUT1_HEIGHT(L1_OUTPUT1_HEIGHT),
.LAYER_OUTPUT2_WIDTH(L1_OUTPUT2_WIDTH),
.LAYER_OUTPUT2_HEIGHT(L1_OUTPUT2_HEIGHT),
.CHANNEL_NUM('d1),
.M0_WIDTH(M0_WIDTH)
) Layer1_inst
(
    .clk(clk),
    .reset(reset),
    .run(run),
    .fm_data_in0(input_data_in0),
	.fm_data_in1(input_data_in1),
    .result_read_addr(l1_read_addr),
    .fm_data_read_addr0(input_mem_read_addr0),
	.fm_data_read_addr1(input_mem_read_addr1),
    .result_out(l1_output),
    .done(l1_done)
);



logic signed [DATA_WIDTH-1:0] l1_bank1_out [2];
logic signed [DATA_WIDTH-1:0] l1_bank2_out [2];
logic signed [DATA_WIDTH-1:0] l1_bank3_out [2];
logic signed [DATA_WIDTH-1:0] l1_bank4_out [2];
logic signed [DATA_WIDTH-1:0] l1_bank5_out [2];
logic signed [DATA_WIDTH-1:0] l1_bank6_out [2];

assign l1_bank1_out[0] = l1_output[0];
assign l1_bank1_out[1] = l1_output[1];
assign l1_bank2_out[0] = l1_output[2];
assign l1_bank2_out[1] = l1_output[3];
assign l1_bank3_out[0] = l1_output[4];
assign l1_bank3_out[1] = l1_output[5];
assign l1_bank4_out[0] = l1_output[6];
assign l1_bank4_out[1] = l1_output[7];
assign l1_bank5_out[0] = l1_output[8];
assign l1_bank5_out[1] = l1_output[9];
assign l1_bank6_out[0] = l1_output[10];
assign l1_bank6_out[1] = l1_output[11];


dual_mem_mux #(.ADDR_WIDTH(ADDR_WIDTH),.DATA_WIDTH(DATA_WIDTH), .NUM_MEM(2))
    bank1_mux (.clk(clk), .reset(reset), .read_addr_in(l2_read_addr),
				.fm_data_in(l1_bank1_out), .read_addr_out(l1_read_addr), .data_out(l2_data_in[0]));
				
dual_mem_mux #(.ADDR_WIDTH(ADDR_WIDTH),.DATA_WIDTH(DATA_WIDTH), .NUM_MEM(2))
    bank2_mux (.clk(clk), .reset(reset), .read_addr_in(l2_read_addr),
				.fm_data_in(l1_bank2_out), .read_addr_out(), .data_out(l2_data_in[1]));
				
dual_mem_mux #(.ADDR_WIDTH(ADDR_WIDTH),.DATA_WIDTH(DATA_WIDTH), .NUM_MEM(2))
    bank3_mux (.clk(clk), .reset(reset), .read_addr_in(l2_read_addr),
				.fm_data_in(l1_bank3_out), .read_addr_out(), .data_out(l2_data_in[2]));
				
dual_mem_mux #(.ADDR_WIDTH(ADDR_WIDTH),.DATA_WIDTH(DATA_WIDTH), .NUM_MEM(2))
    bank4_mux (.clk(clk), .reset(reset), .read_addr_in(l2_read_addr),
				.fm_data_in(l1_bank4_out), .read_addr_out(), .data_out(l2_data_in[3]));
				
dual_mem_mux #(.ADDR_WIDTH(ADDR_WIDTH),.DATA_WIDTH(DATA_WIDTH), .NUM_MEM(2))
    bank5_mux (.clk(clk), .reset(reset), .read_addr_in(l2_read_addr),
				.fm_data_in(l1_bank5_out), .read_addr_out(), .data_out(l2_data_in[4]));
				
dual_mem_mux #(.ADDR_WIDTH(ADDR_WIDTH),.DATA_WIDTH(DATA_WIDTH), .NUM_MEM(2))
    bank6_mux (.clk(clk), .reset(reset), .read_addr_in(l2_read_addr),
				.fm_data_in(l1_bank6_out), .read_addr_out(), .data_out(l2_data_in[5]));
logic l2_run;
assign l2_run = l1_done;

Layer2_Wrapper #(
.DATA_WIDTH(DATA_WIDTH),
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(L2_CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(L2_CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(L2_CONV_FM_WIDTH),
.CONV_FM_HEIGHT(L2_CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(L2_CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(L2_CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(L2_LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(L2_LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM('d6),
.M0_WIDTH(M0_WIDTH)
) Layer2_inst
(
    .clk(clk), .reset(reset),.run(l2_run),
    .fm_data_in(l2_data_in),
    .result_read_addr(mlp_read_addr),
    .fm_data_read_addr(l2_read_addr),
    .result_out(l2_output),
    .done(l2_done)
);


logic signed[DATA_WIDTH-1:0] l2_bank1_out [4];
logic signed[DATA_WIDTH-1:0] l2_bank2_out [4];
logic signed[DATA_WIDTH-1:0] l2_bank3_out [4];
logic signed[DATA_WIDTH-1:0] l2_bank4_out [4];

assign l2_bank1_out[0] = l2_output[0];
assign l2_bank1_out[1] = l2_output[1];
assign l2_bank1_out[2] = l2_output[2];
assign l2_bank1_out[3] = l2_output[3];

assign l2_bank2_out[0] = l2_output[4];
assign l2_bank2_out[1] = l2_output[5];
assign l2_bank2_out[2] = l2_output[6];
assign l2_bank2_out[3] = l2_output[7];

assign l2_bank3_out[0] = l2_output[8];
assign l2_bank3_out[1] = l2_output[9];
assign l2_bank3_out[2] = l2_output[10];
assign l2_bank3_out[3] = l2_output[11];

assign l2_bank4_out[0] = l2_output[12];
assign l2_bank4_out[1] = l2_output[13];
assign l2_bank4_out[2] = l2_output[14];
assign l2_bank4_out[3] = l2_output[15];
//      MLP
logic dense_run;
assign dense_run = l2_done;


Dense_Wrapper#(
.DATA_WIDTH(DATA_WIDTH),
.VEC_SIZE(MLP_VEC_SIZE),
.ADDR_WIDTH(ADDR_WIDTH),
.MAC_NUM(4),
.M0_WIDTH(M0_WIDTH)
) dense_inst
(
.clk(clk), .reset(reset), .run(dense_run),
.q_data_b0_in(l2_bank1_out),
.q_data_b1_in(l2_bank2_out),
.q_data_b2_in(l2_bank3_out),
.q_data_b3_in(l2_bank4_out),
.local_fm_addr(mlp_read_addr),
.classification(classification),
.result(),
.done(done)
);


always_ff @(posedge clk) begin
    if (run)      $display("%t start inference",   $time);
    if (l1_done)  $display("%t L1 done",   $time);
    if (l2_done)  $display("%t L2 done",   $time);
    if (done)     $display("%t TOP done",  $time);
end

endmodule
