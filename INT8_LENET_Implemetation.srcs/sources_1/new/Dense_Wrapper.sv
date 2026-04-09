`timescale 1ns / 1ps

module Dense_Wrapper#(
    parameter DATA_WIDTH = 8,
    parameter VEC_SIZE = 400,
    parameter ARRAY_HEIGHT = 1,
    parameter PARTITION_SIZE = VEC_SIZE,
    parameter ADDR_WIDTH = 10,
    parameter ARRAY_WIDTH = VEC_SIZE,
    parameter ARRAY_SIZE = ARRAY_WIDTH * ARRAY_HEIGHT,
    parameter ITE_NUM = ARRAY_WIDTH/PARTITION_SIZE,
	parameter MAC_NUM = 4,
	parameter M0_WIDTH = 32
)
(
input logic clk, reset, run,

input logic  [DATA_WIDTH-1:0] q_data_b0_in[4],
input logic  [DATA_WIDTH-1:0] q_data_b1_in[4],
input logic  [DATA_WIDTH-1:0] q_data_b2_in[4],
input logic  [DATA_WIDTH-1:0] q_data_b3_in[4],

output logic [ADDR_WIDTH-1:0] local_fm_addr,
output logic [3:0] classification,
output logic  [DATA_WIDTH-1:0] result [10],
output logic done
    );

logic [ADDR_WIDTH-1:0] mlp_addr_out;
logic  [DATA_WIDTH-1:0] mlp_data_in[MAC_NUM];
logic signed [(DATA_WIDTH*10)-1:0] weight_data_in [MAC_NUM]; // 10 neuron (10 x 8 = 80bit width)
logic signed [DATA_WIDTH-1:0] q_weight_in [10][MAC_NUM];

logic  [DATA_WIDTH-1:0] mlp_result_out0;
logic  [DATA_WIDTH-1:0] mlp_result_out1;
logic  [DATA_WIDTH-1:0] mlp_result_out2;
logic  [DATA_WIDTH-1:0] mlp_result_out3;
logic  [DATA_WIDTH-1:0] mlp_result_out4;
logic  [DATA_WIDTH-1:0] mlp_result_out5;
logic  [DATA_WIDTH-1:0] mlp_result_out6;
logic  [DATA_WIDTH-1:0] mlp_result_out7;
logic  [DATA_WIDTH-1:0] mlp_result_out8;
logic  [DATA_WIDTH-1:0] mlp_result_out9;

logic mlp_done;

always_ff @(posedge clk) begin
    if(reset) begin
        done <= 0;
    end
    else done <= mlp_done;
end 

FC_BANK0 FC_BANK_0_inst0 (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(mlp_addr_out), .dina('0), .douta(weight_data_in[0]),
                          .clkb(clk), .enb(1'b1), .web(1'b0), .addrb(mlp_addr_out + 'd100), .dinb('0), .doutb(weight_data_in[1]));
FC_BANK1 FC_BANK_1_inst0 (.clka(clk), .ena(1'b1), .wea(1'b0), .addra(mlp_addr_out), .dina('0), .douta(weight_data_in[2]),
                          .clkb(clk), .enb(1'b1), .web(1'b0), .addrb(mlp_addr_out + 'd100), .dinb('0), .doutb(weight_data_in[3]));

genvar i, j;
generate
    for (i = 0; i < 10; i++) begin : NEURON_LOOP
        for (j = 0; j < MAC_NUM; j++) begin : MAC_LOOP
            assign q_weight_in[i][j] =
                weight_data_in[j][i*DATA_WIDTH +: DATA_WIDTH];
        end
    end
endgenerate

    
BRAM_decoder 
#(
.ADDR_WIDTH(ADDR_WIDTH),
.DATA_WIDTH(DATA_WIDTH),
.NUM_MEM (MAC_NUM)
) decoder4to1_inst0 
(
.clk(clk),.reset(reset),
.read_addr_in(mlp_addr_out),
.fm_data_in(q_data_b0_in),
.read_addr_out(local_fm_addr),
.data_out(mlp_data_in[0])
);
BRAM_decoder 
#(
.ADDR_WIDTH(ADDR_WIDTH),
.DATA_WIDTH(DATA_WIDTH),
.NUM_MEM (MAC_NUM)
) decoder4to1_inst1 
(
.clk(clk),.reset(reset),
.read_addr_in(mlp_addr_out),
.fm_data_in(q_data_b1_in),
.read_addr_out(),
.data_out(mlp_data_in[1])
);
BRAM_decoder 
#(
.ADDR_WIDTH(ADDR_WIDTH),
.DATA_WIDTH(DATA_WIDTH),
.NUM_MEM (MAC_NUM)
) decoder4to1_inst2 
(
.clk(clk),.reset(reset),
.read_addr_in(mlp_addr_out),
.fm_data_in(q_data_b2_in),
.read_addr_out(),
.data_out(mlp_data_in[2])
);
BRAM_decoder 
#(
.ADDR_WIDTH(ADDR_WIDTH),
.DATA_WIDTH(DATA_WIDTH),
.NUM_MEM (MAC_NUM)
) decoder4to1_inst3
(
.clk(clk),.reset(reset),
.read_addr_in(mlp_addr_out),
.fm_data_in(q_data_b3_in),
.read_addr_out(),
.data_out(mlp_data_in[3])
);

mlp_top #(
.DATA_WIDTH(DATA_WIDTH),
.VEC_SIZE(VEC_SIZE),
.ARRAY_HEIGHT(ARRAY_HEIGHT),
.PARTITION_SIZE(PARTITION_SIZE),
.ADDR_WIDTH (ADDR_WIDTH),
.M0_WIDTH(M0_WIDTH),
.MAC_NUM(MAC_NUM)
) mlp_top_inst
(
.clk(clk), .rst(reset), .start(run),
.q_data_in(mlp_data_in),
.q_weight_in(q_weight_in),
.address_out(mlp_addr_out),
.result_out0(mlp_result_out0),
.result_out1(mlp_result_out1),
.result_out2(mlp_result_out2),
.result_out3(mlp_result_out3),
.result_out4(mlp_result_out4),
.result_out5(mlp_result_out5),
.result_out6(mlp_result_out6),
.result_out7(mlp_result_out7),
.result_out8(mlp_result_out8),
.result_out9(mlp_result_out9),
.done(mlp_done)
);
    
sofmax_func #(
.DATA_WIDTH(DATA_WIDTH)
) sofmax_inst
(
	.clk(clk),
	.run(mlp_done),
	.data_in0(mlp_result_out0),
	.data_in1(mlp_result_out1),
	.data_in2(mlp_result_out2),
	.data_in3(mlp_result_out3),
	.data_in4(mlp_result_out4),
	.data_in5(mlp_result_out5),
	.data_in6(mlp_result_out6),
	.data_in7(mlp_result_out7),
	.data_in8(mlp_result_out8),
	.data_in9(mlp_result_out9),
	.hex_out(classification)
);

assign result[0] = mlp_result_out0;
assign result[1] = mlp_result_out1;
assign result[2] = mlp_result_out2;
assign result[3] = mlp_result_out3;
assign result[4] = mlp_result_out4;
assign result[5] = mlp_result_out5;
assign result[6] = mlp_result_out6;
assign result[7] = mlp_result_out7;
assign result[8] = mlp_result_out8;
assign result[9] = mlp_result_out9;

endmodule
