// Author: Do Khanh
// School: UIT
// Description: BRAM decoder/control module. It maps address/control inputs to memory bank selections, drives proper enable paths, and routes data between on-chip storage and compute blocks.

`timescale 1ns/1ps

module BRAM_decoder
#(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 27,
	parameter NUM_MEM = 4
)
(
    input  logic        clk,
    input  logic        reset,
    input  logic [ADDR_WIDTH-1 :0]  read_addr_in,
    input  logic  [DATA_WIDTH-1:0] fm_data_in[NUM_MEM], // iact is unsinged
    output logic [ADDR_WIDTH-1:0]  read_addr_out,
    output logic  [DATA_WIDTH-1:0] data_out
);

    logic [3:0] mem_sel_pipe_1, mem_sel_pipe_2;
    logic [3:0] mem_sel_in;

    always_comb begin
        mem_sel_in = read_addr_in / 25;
        read_addr_out    = read_addr_in % 25;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            mem_sel_pipe_1 <= 0;
            mem_sel_pipe_2 <= 0;
        end else begin
            mem_sel_pipe_1 <= mem_sel_in;
            mem_sel_pipe_2 <= mem_sel_pipe_1;
        end
    end

    assign data_out = fm_data_in[mem_sel_pipe_2];

endmodule