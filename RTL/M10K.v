`timescale 1ns / 1ps
// =============================================================================
// Author      : Khanh
// Title       : M10K
// Description : Synchronous single-port read / write memory model inferred as
//               M10K-compatible RAM for simulation and synthesis.
// =============================================================================
module M10K#(
    parameter ITE_NUM = 100,
    parameter DATA_WIDTH = 10,
    parameter ADDR_WIDTH = 10
)
(
    output reg signed [DATA_WIDTH - 1:0] q_out,
    input  wire signed [DATA_WIDTH - 1:0] d_in,
    input  wire [ADDR_WIDTH - 1:0] write_address_in, read_address_in,
    input  wire we_in, clk_in
);
	 // force M10K ram style
	 // 307200 words of 8 bits
    reg [DATA_WIDTH-1:0] mem [ITE_NUM-1:0]  /* synthesis ramstyle = "no_rw_check, M10K" */;
	reg [DATA_WIDTH - 1:0] out_q;
    reg [DATA_WIDTH - 1:0] out_q_r;

    always @ (posedge clk_in) begin
        if (we_in) begin
            mem[write_address_in] <= d_in;
		  end
        out_q_r <= mem[read_address_in];
		q_out <= out_q_r;
	 end
endmodule