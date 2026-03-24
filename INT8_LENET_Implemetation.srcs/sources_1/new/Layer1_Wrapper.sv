`timescale 1ns / 1ps

module Layer1_Wrapper #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10,
    parameter CONV_KERNEL_WIDTH = 3,
    parameter CONV_KERNEL_HEIGHT = 3,
    parameter IMAGE_BANK1_WIDTH = 28,
    parameter IMAGE_BANK1_HEIGHT = 14,
	parameter IMAGE_BANK2_WIDTH = 28,
    parameter IMAGE_BANK2_HEIGHT = 16,
    parameter CONV_RESULT1_WIDTH = 26,
    parameter CONV_RESULT1_HEIGHT = 12,
	parameter CONV_RESULT2_WIDTH = 26,
    parameter CONV_RESULT2_HEIGHT = 14,
    parameter POOL_KERNEL_WIDTH = 2,
    parameter POOL_KERNEL_HEIGHT = 2,
    parameter LAYER_OUTPUT1_WIDTH = 13,
    parameter LAYER_OUTPUT1_HEIGHT = 6,
	parameter LAYER_OUTPUT2_WIDTH = 13,
    parameter LAYER_OUTPUT2_HEIGHT = 7,
    parameter CHANNEL_NUM = 1,
	parameter M0_WIDTH = 32
	)
	(
    input logic clk, reset, run,
    input logic signed [DATA_WIDTH-1:0] fm_data_in0 [CHANNEL_NUM],
	input logic signed [DATA_WIDTH-1:0] fm_data_in1 [CHANNEL_NUM],
    input logic [ADDR_WIDTH-1:0] result_read_addr,
    
    output logic [ADDR_WIDTH-1:0] fm_data_read_addr0,
	output logic [ADDR_WIDTH-1:0] fm_data_read_addr1,
	
    output logic signed [DATA_WIDTH-1:0] result_out[12],
    output logic done
	);

	logic is_last_fm_addr0, is_last_fm_addr1;
	logic update_fm_begin_addr0, update_fm_begin_addr1;
	logic fm_gen_addr_en0, fm_gen_addr_en1;
	
	logic signed [DATA_WIDTH-1:0] layer_result_op[12];
	logic signed [(DATA_WIDTH*6)-1:0] weight_data_in; // 6 filters ( 6 * 8 = 48 bits)
	
	logic signed [DATA_WIDTH-1:0] weight_data_in_F0 [CHANNEL_NUM];
	logic signed [DATA_WIDTH-1:0] weight_data_in_F1 [CHANNEL_NUM];
	logic signed [DATA_WIDTH-1:0] weight_data_in_F2 [CHANNEL_NUM];
	logic signed [DATA_WIDTH-1:0] weight_data_in_F3 [CHANNEL_NUM];
	logic signed [DATA_WIDTH-1:0] weight_data_in_F4 [CHANNEL_NUM];
	logic signed [DATA_WIDTH-1:0] weight_data_in_F5 [CHANNEL_NUM];
	
	logic [ADDR_WIDTH-1:0] weight_read_addr;
    
	generate
		genvar i;
		for (i = 0; i < 12; i++) begin
			assign result_out[i] = layer_result_op[i];
		end
	endgenerate
	
	logic done1, done2;
	assign done = done2;

// handling bank1 memory fetching logic
	logic [ADDR_WIDTH-1:0] column_count0;
	logic [ADDR_WIDTH-1:0] row_count0;

	assign is_last_fm_addr0 = (column_count0 == IMAGE_BANK1_WIDTH - CONV_KERNEL_WIDTH) && (row_count0 == IMAGE_BANK1_HEIGHT - CONV_KERNEL_HEIGHT);
		
	always@(posedge clk) begin
		if (reset) begin
		  column_count0 <= 'b0;
		  row_count0 <= 'b0;
		end
		else if (update_fm_begin_addr0) begin
		  column_count0 <= (column_count0 < IMAGE_BANK1_WIDTH - CONV_KERNEL_WIDTH) ? column_count0 + 'b1 : 'b0;
		  row_count0 <= is_last_fm_addr0 ? 'b0 : (column_count0 == IMAGE_BANK1_WIDTH - CONV_KERNEL_WIDTH) ? row_count0 + 'b1 : row_count0;
		end
	end

	logic [ADDR_WIDTH-1:0] fm_begin_addr0 = 'd0 ;

	always@(posedge clk) begin
		if (reset) begin
		  fm_begin_addr0 <= 'b0;
		end
		else if (update_fm_begin_addr0) begin
		  fm_begin_addr0 <= is_last_fm_addr0 ? 'b0 : (column_count0 == IMAGE_BANK1_WIDTH - CONV_KERNEL_WIDTH) ? fm_begin_addr0 + CONV_KERNEL_WIDTH : fm_begin_addr0 + 'd1;
		end
	end
	
// handling bank1 memory fetching logic
	logic [ADDR_WIDTH-1:0] column_count1;
	logic [ADDR_WIDTH-1:0] row_count1;

	assign is_last_fm_addr1 = (column_count1 == IMAGE_BANK2_WIDTH - CONV_KERNEL_WIDTH) && (row_count1 == IMAGE_BANK2_HEIGHT - CONV_KERNEL_HEIGHT);
		
	always@(posedge clk) begin
		if (reset) begin
		  column_count1 <= 'b0;
		  row_count1 <= 'b0;
		end
		else if (update_fm_begin_addr1) begin
		  column_count1 <= (column_count1 < IMAGE_BANK2_WIDTH - CONV_KERNEL_WIDTH) ? column_count1 + 'b1 : 'b0;
		  row_count1 <= is_last_fm_addr1 ? 'b0 : (column_count1 == IMAGE_BANK2_WIDTH - CONV_KERNEL_WIDTH) ? row_count1 + 'b1 : row_count1;
		end
	end

	logic [ADDR_WIDTH-1:0] fm_begin_addr1 = 'd0 ;

	always@(posedge clk) begin
		if (reset) begin
		  fm_begin_addr1 <= 'b0;
		end
		else if (update_fm_begin_addr1) begin
		  fm_begin_addr1 <= is_last_fm_addr1 ? 'b0 : (column_count1 == IMAGE_BANK2_WIDTH - CONV_KERNEL_WIDTH) ? fm_begin_addr1 + CONV_KERNEL_WIDTH : fm_begin_addr1 + 'd1;
		end
	end	
	
	


	read_address_gen #(
    .ARRAY_HEIGHT  (IMAGE_BANK1_HEIGHT),
    .ARRAY_WIDTH   (IMAGE_BANK1_WIDTH),
    .PARTITION_SIZE(CONV_KERNEL_WIDTH),
    .PARTITION_HEIGHT(CONV_KERNEL_HEIGHT)
  ) gen_addr_bank1 (
    .clk        (clk),
    .run        (fm_gen_addr_en0),
    .begin_addr (fm_begin_addr0),
    .addr_out   (fm_data_read_addr0),
    .wr_addr    (),
    .done       ()
 );

	read_address_gen #(
    .ARRAY_HEIGHT  (IMAGE_BANK2_HEIGHT),
    .ARRAY_WIDTH   (IMAGE_BANK2_WIDTH),
    .PARTITION_SIZE(CONV_KERNEL_WIDTH),
    .PARTITION_HEIGHT(CONV_KERNEL_HEIGHT)
  ) gen_addr_bank2 (
    .clk        (clk),
    .run        (fm_gen_addr_en1),
    .begin_addr (fm_begin_addr1),
    .addr_out   (fm_data_read_addr1),
    .wr_addr    (),
    .done       ()
 );
 
 Layer1_weights Layer1_weights_inst (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in));
 
 assign weight_data_in_F0[0] = weight_data_in [7:0];
 assign weight_data_in_F1[0] = weight_data_in [15:8];
 assign weight_data_in_F2[0] = weight_data_in [23:16];
 assign weight_data_in_F3[0] = weight_data_in [31:24];
 assign weight_data_in_F4[0] = weight_data_in [39:32];
 assign weight_data_in_F5[0] = weight_data_in [47:40];
 
 // Filter 0
	L1_F0_0_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK1_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK1_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT1_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT1_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT1_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT1_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F0_0_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in0),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr0),
	.update_fm_begin_addr(update_fm_begin_addr0),
	.fm_gen_addr_en(fm_gen_addr_en0),
	.result_out(layer_result_op[0]),
	.done(done1),
	.weight_data_in(weight_data_in_F0),
	.weight_read_addr()
	);
	
	L1_F0_1_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK2_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK2_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT2_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT2_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT2_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT2_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F0_1_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in1),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr1),
	.update_fm_begin_addr(update_fm_begin_addr1),
	.fm_gen_addr_en(fm_gen_addr_en1),
	.result_out(layer_result_op[1]),
	.done(done2),
	.weight_data_in(weight_data_in_F0),
	.weight_read_addr(weight_read_addr)
	);
	
 // filter 1
	L1_F1_0_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK1_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK1_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT1_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT1_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT1_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT1_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F1_0_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in0),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr0),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[2]),
	.done(),
	.weight_data_in(weight_data_in_F1),
	.weight_read_addr()
	);
	
	L1_F1_1_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK2_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK2_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT2_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT2_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT2_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT2_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F1_1_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in1),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr1),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[3]),
	.done(),
	.weight_data_in(weight_data_in_F1),
	.weight_read_addr()
	);
	
// filter 2	
	L1_F2_0_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK1_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK1_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT1_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT1_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT1_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT1_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F2_0_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in0),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr0),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[4]),
	.done(),
	.weight_data_in(weight_data_in_F2),
	.weight_read_addr()
	);
	
	L1_F2_1_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK2_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK2_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT2_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT2_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT2_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT2_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F2_1_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in1),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr1),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[5]),
	.done(),
	.weight_data_in(weight_data_in_F2),
	.weight_read_addr()
	);
//filter 3	
	L1_F3_0_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK1_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK1_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT1_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT1_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT1_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT1_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F3_0_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in0),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr0),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[6]),
	.done(),
	.weight_data_in(weight_data_in_F3),
	.weight_read_addr()
	);
	
	L1_F3_1_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK2_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK2_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT2_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT2_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT2_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT2_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F3_1_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in1),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr1),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[7]),
	.done(),
	.weight_data_in(weight_data_in_F3),
	.weight_read_addr()
	);
// filter 4
	L1_F4_0_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK1_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK1_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT1_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT1_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT1_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT1_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F4_0_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in0),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr0),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[8]),
	.done(),
	.weight_data_in(weight_data_in_F4),
	.weight_read_addr()
	);
	
	L1_F4_1_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK2_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK2_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT2_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT2_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT2_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT2_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F4_1_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in1),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr1),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[9]),
	.done(),
	.weight_data_in(weight_data_in_F4),
	.weight_read_addr()
	);	
	
// filter 5
	L1_F5_0_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK1_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK1_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT1_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT1_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT1_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT1_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F5_0_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in0),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr0),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[10]),
	.done(),
	.weight_data_in(weight_data_in_F5),
	.weight_read_addr()
	);
	
	L1_F5_1_process_unit #(
	.DATA_WIDTH(DATA_WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
	.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
	.CONV_FM_WIDTH(IMAGE_BANK2_WIDTH),
	.CONV_FM_HEIGHT(IMAGE_BANK2_HEIGHT),
	.CONV_RESULT_WIDTH(CONV_RESULT2_WIDTH),
	.CONV_RESULT_HEIGHT(CONV_RESULT2_HEIGHT),
	.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
	.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
	.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT2_WIDTH),
	.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT2_HEIGHT),
	.CHANNEL_NUM(CHANNEL_NUM),
	.M0_WIDTH(M0_WIDTH)
	) F5_1_process_branch
	(
	.clk(clk), .reset(reset), .run(run),
	.fm_data_in(fm_data_in1),
	.result_read_addr(result_read_addr),
	.is_last_fm_addr(is_last_fm_addr1),
	.update_fm_begin_addr(),
	.fm_gen_addr_en(),
	.result_out(layer_result_op[11]),
	.done(),
	.weight_data_in(weight_data_in_F5),
	.weight_read_addr()
	);
	
endmodule