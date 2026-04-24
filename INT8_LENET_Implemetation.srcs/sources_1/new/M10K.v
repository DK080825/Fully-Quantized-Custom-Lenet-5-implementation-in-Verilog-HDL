// Author: Do Khanh
// School: UIT
// Description: M10K memory wrapper/definition for FPGA embedded RAM resources. It provides reusable on-chip storage interfaces for model parameters and intermediate feature maps with low-latency access.

`timescale 1ns / 1ps
module M10K#(
    parameter ITE_NUM = 100,
    parameter DATA_WIDTH = 10,
    parameter ADDR_WIDTH = 10
)
(
    output logic signed [DATA_WIDTH - 1:0] q,
    input logic signed [DATA_WIDTH - 1:0] d,
    input logic [ADDR_WIDTH - 1:0] write_address, read_address,
    input logic we, clk
);
	 // force M10K ram style
	 // 307200 words of 8 bits
    logic [DATA_WIDTH-1:0] mem [ITE_NUM-1:0]  /* synthesis ramstyle = "no_rw_check, M10K" */;
	logic [DATA_WIDTH - 1:0] out_q;
    always @ (posedge clk) begin
        if (we) begin
            mem[write_address] <= d;
		  end
        out_q <= mem[read_address]; // q doesn't get d in this clock cycle
		q <= out_q;
	 end
endmodule