`timescale 1ns / 1ps

module mlp_top #(
    parameter DATA_WIDTH = 8,
    parameter VEC_SIZE = 400,
    parameter ARRAY_HEIGHT = 1,
    parameter PARTITION_SIZE = 400,
    parameter ADDR_WIDTH = 10,
	parameter M0_WIDTH = 32,
    parameter ARRAY_WIDTH = VEC_SIZE,
    parameter ARRAY_SIZE = ARRAY_WIDTH * ARRAY_HEIGHT,
    parameter ITE_NUM = ARRAY_WIDTH/PARTITION_SIZE,
	parameter MAC_NUM = 4
    )
(
    input logic clk, rst, start,
    input logic signed [DATA_WIDTH-1 :0] q_data_in[MAC_NUM],
    input logic signed [DATA_WIDTH-1 :0] q_weight_in [10][MAC_NUM],
    
    output logic [ADDR_WIDTH -1: 0] address_out,
    output logic signed [DATA_WIDTH-1:0] result_out0,
    output logic signed [DATA_WIDTH-1:0] result_out1,
    output logic signed [DATA_WIDTH-1:0] result_out2,
    output logic signed [DATA_WIDTH-1:0] result_out3,
    output logic signed [DATA_WIDTH-1:0] result_out4,
    output logic signed [DATA_WIDTH-1:0] result_out5,
    output logic signed [DATA_WIDTH-1:0] result_out6,
    output logic signed [DATA_WIDTH-1:0] result_out7,
    output logic signed [DATA_WIDTH-1:0] result_out8,
    output logic signed [DATA_WIDTH-1:0] result_out9,
    output logic done
);


//////////FSM controller//////////////

localparam int STATE_IDLE = 'd0;
localparam int STATE_STREAM = 'd1;
localparam int STATE_DONE = 'd2;
localparam int PE_NUM = 10;

logic stream_en = 'b0;
logic PE_en = 'b0;
logic PE_en_pipe0 = 'b0;
logic PE_en_pipe1 = 'b0;

logic all_PE_done;
logic  [PE_NUM-1:0] single_PE_done;
assign all_PE_done = &(single_PE_done);

logic [1:0] state_reg, state_next;
logic signed [DATA_WIDTH-1:0] vec_dot_out [PE_NUM-1:0];
logic signed[DATA_WIDTH-1:0]  vec_dot_next [PE_NUM-1:0];
logic signed [DATA_WIDTH-1:0] vec_dot_reg [PE_NUM-1:0];

// clear and last signals logic for INT8 MAC 
logic clr_acc, last_acc;
localparam WINDOW_SIZE = VEC_SIZE/MAC_NUM; // 400/4 = 100
logic [$clog2(WINDOW_SIZE):0] mac_count;

always @(posedge clk) begin
    if (rst)
        mac_count <= 0;
    else if (PE_en) begin
        if (mac_count == WINDOW_SIZE-1)
            mac_count <= 0;
        else
            mac_count <= mac_count + 1;
    end
end

assign clr_acc = (PE_en && mac_count == 0)? 1 : 0;
assign last_acc = (PE_en && mac_count == WINDOW_SIZE-1)? 1 : 0;


assign result_out0 = vec_dot_reg[0];
assign result_out1 = vec_dot_reg[1];
assign result_out2 = vec_dot_reg[2];
assign result_out3 = vec_dot_reg[3];
assign result_out4 = vec_dot_reg[4];
assign result_out5 = vec_dot_reg[5];
assign result_out6 = vec_dot_reg[6];
assign result_out7 = vec_dot_reg[7];
assign result_out8 = vec_dot_reg[8];
assign result_out9 = vec_dot_reg[9];

integer it;


always_ff @(posedge clk) begin
	if(rst) begin
		state_reg <= STATE_IDLE;
		for (it = 0; it< PE_NUM;it++) begin 
			vec_dot_reg[it] <= 'd0;
		end 
	end
	else begin
		state_reg <= state_next;
		for (it = 0; it< PE_NUM;it++) begin 
			vec_dot_reg[it]<= vec_dot_next[it];
		end 
	end
end

always_ff @(posedge clk) begin
	if(rst) begin
		PE_en <= 0;
		PE_en_pipe1  <= 0;
	end
	else begin
		PE_en_pipe1 <= PE_en_pipe0;
		PE_en <= PE_en_pipe1;
	end
end

integer i;
always_comb begin

	//default assignment
	state_next = STATE_IDLE;
	stream_en = 'd0;
	done = 0;
	PE_en_pipe0 = 0;
	
	//---------STATE IDLE---------------
	if (state_reg == STATE_IDLE) begin
		done = 0;
		PE_en_pipe0 = 0;
		stream_en = 0;
		for (i = 0; i< PE_NUM;i++) begin 
			vec_dot_next[i] = 'd0;
		end 
		if (start == 1'b1) begin
			state_next = STATE_STREAM;
		end
		else state_next = state_reg;
		
	end
	
	//---------STATE STREAM---------------
	else if ( state_reg == STATE_STREAM) begin
		done  = 0;
		PE_en_pipe0 = 1;
		stream_en = 1;
		for (i = 0; i< PE_NUM;i++) begin 
			vec_dot_next[i] = vec_dot_out[i];
		end 
		if(all_PE_done == 1'b1) state_next = STATE_DONE;
		else state_next = state_reg;
	end 
	
	
	//---------STATE DONE---------------
	else if (state_reg == STATE_DONE) begin
		done = 1;
		PE_en_pipe0 = 0;
		stream_en = 0;
		for (i = 0; i< PE_NUM;i++) begin 
			vec_dot_next[i] = vec_dot_reg[i];
		end 
		state_next = state_reg;
	end
	
end
/////////DATA_PATH////////////////////
read_address_gen #(
	.ARRAY_HEIGHT('d1),
	.PARTITION_SIZE(VEC_SIZE/MAC_NUM),
	.ARRAY_SIZE(VEC_SIZE/MAC_NUM),
	.ARRAY_WIDTH(VEC_SIZE/MAC_NUM)
)
read_address_gen
(
	.clk(clk), 
	.run(stream_en),
	.begin_addr('d0),
    .addr_out(address_out), 
	.wr_addr(), 
	.done()
);

// Note: Z_data_in, Z_out is the same for all neurons
//		 Z_weight_in, M0_in, n_in, bias_in is different for each neuron
INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
) mac_neuron0
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[0]),
 .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d1798618152), .n_in('d9), .bias_in('d133),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[0]), .Q3_valid_out(single_PE_done[0])
);

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
)mac_neuron1
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[1]),
  .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d1893381934), .n_in('d9), .bias_in('d121),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[1]), .Q3_valid_out(single_PE_done[1])
);

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
)mac_neuron2
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[2]),
  .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d2011248985), .n_in('d9), .bias_in(-'d40),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[2]), .Q3_valid_out(single_PE_done[2])
);

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
) mac_neuron3
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[3]),
  .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d1997046003), .n_in('d9), .bias_in(-'d45),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[3]), .Q3_valid_out(single_PE_done[3])
);

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
)mac_neuron4
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[4]),
  .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d1604336325), .n_in('d9), .bias_in(-'d26),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[4]), .Q3_valid_out(single_PE_done[4])
);

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
) mac_neuron5
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[5]),
  .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d1110916924), .n_in('d8), .bias_in('d85),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[5]), .Q3_valid_out(single_PE_done[5])
);

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
)mac_neuron6
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[6]),
  .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d1812078817), .n_in('d9), .bias_in(-'d73),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[6]), .Q3_valid_out(single_PE_done[6])
);

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
) mac_neuron7
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[7]),
  .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d1792013371), .n_in('d9), .bias_in(-'d10),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[7]), .Q3_valid_out(single_PE_done[7])
);

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
) mac_neuron8
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[8]),
  .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d1090754087), .n_in('d8), .bias_in('d20),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[8]), .Q3_valid_out(single_PE_done[8])
);

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(MAC_NUM)
) mac_neuron9
(
 .CLK (clk), .RST(rst),
 .Qa_in(q_data_in), .Qw_in(q_weight_in[9]),
  .Za_in('d75), .Zw_in('d0), .Zo_in('d69),
 .En_in(PE_en),
 .M0_in('d1092942666), .n_in('d8), .bias_in('d29),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(vec_dot_out[9]), .Q3_valid_out(single_PE_done[9])
);

endmodule

