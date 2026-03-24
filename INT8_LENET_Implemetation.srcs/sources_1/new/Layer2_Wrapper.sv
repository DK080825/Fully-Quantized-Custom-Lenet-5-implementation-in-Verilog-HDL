`timescale 1ns / 1ps

module Layer2_Wrapper
#(
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
)(
    input logic clk, reset, run,
    input logic signed [DATA_WIDTH-1:0] fm_data_in [6],
    input logic [ADDR_WIDTH-1:0] result_read_addr,
    
    output logic [ADDR_WIDTH-1:0] fm_data_read_addr,
    output logic signed [DATA_WIDTH-1:0] result_out[16],
    output logic done
);

logic is_last_fm_addr;
logic update_fm_begin_addr;
logic fm_gen_addr_en;
logic signed [DATA_WIDTH-1:0] layer_result_op[16];
logic signed [(DATA_WIDTH*6)-1:0] weight_data_in [16]; // 16 filters X 6 channels x 8bit data ==> 
logic signed [DATA_WIDTH-1:0] weight_data_in_F [16][6];
logic [ADDR_WIDTH-1:0] weight_read_addr;

generate
    genvar i;
    for (i = 0; i < 16; i++) begin
        assign result_out[i] = layer_result_op[i];
    end
endgenerate


logic [ADDR_WIDTH-1:0] column_count;
logic [ADDR_WIDTH-1:0] row_count;

assign is_last_fm_addr = (column_count == CONV_FM_WIDTH - CONV_KERNEL_WIDTH) && (row_count == CONV_FM_HEIGHT - CONV_KERNEL_HEIGHT);
	
always@(posedge clk) begin
	if (reset) begin
	  column_count <= 'b0;
	  row_count <= 'b0;
	end
	else if (update_fm_begin_addr) begin
	  column_count <= (column_count < CONV_FM_WIDTH - CONV_KERNEL_WIDTH) ? column_count + 'b1 : 'b0;
	  row_count <= is_last_fm_addr ? 'b0 : (column_count == CONV_FM_WIDTH - CONV_KERNEL_WIDTH) ? row_count + 'b1 : row_count;
    end
end

logic [ADDR_WIDTH-1:0] fm_begin_addr = 'd0 ;

always@(posedge clk) begin
	if (reset) begin
	  fm_begin_addr <= 'b0;
    end
	else if (update_fm_begin_addr) begin
	  fm_begin_addr <= is_last_fm_addr ? 'b0 : (column_count == CONV_FM_WIDTH - CONV_KERNEL_WIDTH) ? fm_begin_addr + CONV_KERNEL_WIDTH : fm_begin_addr + 'd1;
    end
end



 read_address_gen #(
    .ARRAY_HEIGHT  (CONV_FM_HEIGHT),
    .ARRAY_WIDTH   (CONV_FM_WIDTH),
    .PARTITION_SIZE(CONV_KERNEL_WIDTH),
    .PARTITION_HEIGHT(CONV_KERNEL_HEIGHT)
  ) dut (
    .clk        (clk),
    .run        (fm_gen_addr_en),
    .begin_addr (fm_begin_addr),
    .addr_out   (fm_data_read_addr),
    .wr_addr    (),
    .done       ()
 );

 Layer2_F0 Layer2_weights_inst0    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[0]));
 Layer2_F1 Layer2_weights_inst1    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[1]));
 Layer2_F2 Layer2_weights_inst2    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[2]));
 Layer2_F3 Layer2_weights_inst3    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[3]));
 Layer2_F4 Layer2_weights_inst4    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[4]));
 Layer2_F5 Layer2_weights_inst5    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[5]));
 Layer2_F6 Layer2_weights_inst6    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[6]));
 Layer2_F7 Layer2_weights_inst7    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[7]));
 Layer2_F8 Layer2_weights_inst8    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[8]));
 Layer2_F9 Layer2_weights_inst9    (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[9]));
 Layer2_F10 Layer2_weights_inst10 (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[10]));
 Layer2_F11 Layer2_weights_inst11 (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[11]));
 Layer2_F12 Layer2_weights_inst12 (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[12]));
 Layer2_F13 Layer2_weights_inst13 (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[13]));
 Layer2_F14 Layer2_weights_inst14 (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[14]));
 Layer2_F15 Layer2_weights_inst15 (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(weight_read_addr), .dina('0), .douta(weight_data_in[15]));
 
generate
    genvar j;
    for (i = 0; i < 16; i++) begin : FILTER_LOOP
        for (j = 0; j < 6; j++) begin : CHANNEL_LOOP
            assign weight_data_in_F[i][j] = weight_data_in [i] [j*DATA_WIDTH +: DATA_WIDTH];
        end
    end
endgenerate

// Instances are written explicitly instead of using a generate-for loop,
// because each L2_Fx_process_unit is bound to a unique weight set.

L2_F0_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F0_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(update_fm_begin_addr),
.fm_gen_addr_en(fm_gen_addr_en),
.result_out(layer_result_op[0]),
.done(done),
.weight_data_in(weight_data_in_F[0]),
.weight_read_addr(weight_read_addr)
);

L2_F1_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F1_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[1]),
.done(),
.weight_data_in(weight_data_in_F[1]),
.weight_read_addr()
);

L2_F2_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F2_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[2]),
.done(),
.weight_data_in(weight_data_in_F[2]),
.weight_read_addr()
);

L2_F3_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F3_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[3]),
.done(),
.weight_data_in(weight_data_in_F[3]),
.weight_read_addr()
);

L2_F4_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F4_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[4]),
.done(),
.weight_data_in(weight_data_in_F[4]),
.weight_read_addr()
);

L2_F5_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F5_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[5]),
.done(),
.weight_data_in(weight_data_in_F[5]),
.weight_read_addr()
);

L2_F6_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F6_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[6]),
.done(),
.weight_data_in(weight_data_in_F[6]),
.weight_read_addr()
);

L2_F7_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F7_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[7]),
.done(),
.weight_data_in(weight_data_in_F[7]),
.weight_read_addr()
);

L2_F8_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F8_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[8]),
.done(),
.weight_data_in(weight_data_in_F[8]),
.weight_read_addr()
);

L2_F9_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F9_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[9]),
.done(),
.weight_data_in(weight_data_in_F[9]),
.weight_read_addr()
);

L2_F10_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F10_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[10]),
.done(),
.weight_data_in(weight_data_in_F[10]),
.weight_read_addr()
);

L2_F11_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F11_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[11]),
.done(),
.weight_data_in(weight_data_in_F[11]),
.weight_read_addr()
);

L2_F12_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F12_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[12]),
.done(),
.weight_data_in(weight_data_in_F[12]),
.weight_read_addr()
);

L2_F13_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F13_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[13]),
.done(),
.weight_data_in(weight_data_in_F[13]),
.weight_read_addr()
);

L2_F14_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F14_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[14]),
.done(),
.weight_data_in(weight_data_in_F[14]),
.weight_read_addr()
);

L2_F15_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F15_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[15]),
.done(),
.weight_data_in(weight_data_in_F[15]),
.weight_read_addr()
);


endmodule
