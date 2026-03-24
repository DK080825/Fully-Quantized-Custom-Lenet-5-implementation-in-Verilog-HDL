`timescale 1ns / 1ps

module Maxpooling2x2_Relu #(
	parameter DATA_WIDTH = 8,
	parameter ADDR_WIDTH = 10
)
(
    input logic run, clk, reset,
    input logic signed [DATA_WIDTH-1:0] data_in,
    input clear, //update for another windwon
    input logic signed [DATA_WIDTH-1:0] Zo_in,
    output logic signed [DATA_WIDTH-1:0] result_out,
    output logic [ADDR_WIDTH-1:0] address_out
);

logic signed [DATA_WIDTH-1:0] result_reg;
logic signed [DATA_WIDTH-1:0] result_next;
logic [ADDR_WIDTH-1:0] address_out_reg = 'd0;
logic [ADDR_WIDTH-1:0] address_out_next;

assign result_out = result_reg;
assign address_out = address_out_reg;

always_ff @(posedge clk) begin
    if(reset) begin
        result_reg <= Zo_in;
        address_out_reg <= 0;
    end
    else begin
        result_reg <= result_next;
        address_out_reg <= address_out_next;
    end
end

always_comb begin
    result_next = result_reg;
    address_out_next = address_out_reg;
    if(run) begin
        result_next = (data_in > result_reg)? data_in: result_reg;
    end
    else if(clear) begin
        result_next = Zo_in;
        address_out_next = address_out_reg + 'd1;
    end
end
endmodule
