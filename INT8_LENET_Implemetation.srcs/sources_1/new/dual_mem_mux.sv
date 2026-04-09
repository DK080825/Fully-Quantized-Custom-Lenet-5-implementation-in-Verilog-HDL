`timescale 1ns/1ps

module dual_mem_mux
#(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 8,
    parameter NUM_MEM = 2
)
(
    input  logic clk,
    input  logic reset,

    input  logic  [ADDR_WIDTH-1:0] read_addr_in,
    input  logic  [DATA_WIDTH-1:0] fm_data_in[NUM_MEM],

    output logic [ADDR_WIDTH-1:0] read_addr_out,
    output logic  [DATA_WIDTH-1:0] data_out
);

    logic mem_sel_in;
    logic mem_sel_pipe_1, mem_sel_pipe_2;

    // address decode
    always_comb begin
        if (read_addr_in < 78) begin
            mem_sel_in   = 0;
            read_addr_out = read_addr_in;
        end
        else begin
            mem_sel_in   = 1;
            read_addr_out = read_addr_in - 78;
        end
    end

    // pipeline (to match BRAM latency)
    always_ff @(posedge clk) begin
        if (reset) begin
            mem_sel_pipe_1 <= 0;
            mem_sel_pipe_2 <= 0;
        end
        else begin
            mem_sel_pipe_1 <= mem_sel_in;
            mem_sel_pipe_2 <= mem_sel_pipe_1;
        end
    end

    assign data_out = fm_data_in[mem_sel_pipe_2];

endmodule