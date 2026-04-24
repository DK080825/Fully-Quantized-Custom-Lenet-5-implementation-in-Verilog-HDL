// Author: Do Khanh
// School: UIT
// Description: Fixed-pattern address generator. It produces deterministic sequential/tiled memory addresses for convolution/pooling traversal and keeps memory access aligned with pipeline cycle timing.

module read_address_gen #(
	parameter ARRAY_HEIGHT=10,
	parameter PARTITION_SIZE=5,
	parameter ADDR_WIDTH = 10,
	parameter ARRAY_WIDTH=75,
	parameter ARRAY_SIZE= ARRAY_HEIGHT * ARRAY_WIDTH,
	parameter PARTITION_HEIGHT = ARRAY_HEIGHT
	//default = ARRAY_HEIGHT => for mlp
	//for sliding window => PARTITION_HEIGHT = KERNEL_HEIGHT
)
(
	clk, run,begin_addr,
   addr_out, wr_addr, done	
	
);

input logic clk, run;
input logic [ADDR_WIDTH-1:0] begin_addr;
output logic [ADDR_WIDTH-1:0] addr_out;
output logic [ADDR_WIDTH-1:0] wr_addr;
output logic done;


logic [$clog2(PARTITION_SIZE)-1:0] column_count;
logic [$clog2(ARRAY_HEIGHT)-1:0] row_count;
logic [ADDR_WIDTH-1:0] wr_addr_pipe ; // delay wr_addr for correct loading

//handling done signal


always @(posedge clk) begin
	if(!run) begin
		column_count <= 0;
		row_count <= 0;
		wr_addr <= 0;
		wr_addr_pipe <= 0;
		done <= 0;
	end
	else begin
		column_count <= (column_count < PARTITION_SIZE - 1)? column_count + 'b1: 0;
		row_count <= (column_count == PARTITION_SIZE -1)? row_count + 'b1: row_count;
		done <= ((column_count == PARTITION_SIZE - 2) && ( row_count == PARTITION_HEIGHT - 1))? 1'b1 : done;
		wr_addr_pipe <= (wr_addr_pipe < (PARTITION_SIZE*ARRAY_HEIGHT -1)) ? wr_addr_pipe + 1'b1 : wr_addr_pipe;
		wr_addr <= wr_addr_pipe;
	end
end

always @(posedge clk) begin
	if(!run) 
		addr_out <= begin_addr;
	else
		addr_out <= (done)? addr_out : (column_count < PARTITION_SIZE-1)? addr_out + 'b1: addr_out + (ARRAY_WIDTH-PARTITION_SIZE+1);
	
end

endmodule