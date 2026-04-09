module MAC_wrapper #(
 parameter KERNEL_WIDTH = 3,
 parameter KERNEL_HEIGHT = 3,
 parameter FM_WIDTH = 9,
 parameter FM_HEIGHT = 9,
 parameter DATA_WIDTH = 8,
 parameter ADDR_WIDTH = 100,
 parameter M0_WIDTH = 32,
 parameter CHANNEL_PAR = 6
)
(   input logic clk,
    input logic reset,
    input logic run,
    input logic signed [DATA_WIDTH-1:0] q_weight_in [CHANNEL_PAR],
    input logic          [DATA_WIDTH-1:0] q_data_in [CHANNEL_PAR], // unsigned
	input logic signed [DATA_WIDTH-1:0] Z_weight_in,
	input logic         [DATA_WIDTH-1:0] Z_data_in,
	input logic         [DATA_WIDTH-1:0] Zo_in,
	input logic signed [M0_WIDTH-1:0] 	M0_in,
    input logic signed [31:0] 			bias_in,
	input logic 	   [5:0]        	n_in,
    
    input logic is_last_begin_addr,
    output logic update_data_addr_out,
    
    output logic [ADDR_WIDTH-1:0] wt_read_addr_out,
    output logic fm_gen_addr_en,
    output logic     [DATA_WIDTH-1:0] q_out, // unsigned
    output logic [ADDR_WIDTH-1:0] wr_addr_out,
    output logic we_out,
    output logic done,
    
    // for testing
    output logic MAC_en,
    output logic [8:0] MAC_counter,
    output logic clr_sig,
    output logic last_sig
    );

typedef enum
{ STATE_WAIT,
  STATE_STREAM_DATA,
  STATE_UPDATE_WINDOW,
  STATE_UPDATE_WAIT,
  STATE_WAIT_FINISHED,
  STATE_FINISHED
  } states;
  
states current_state, next_state;
logic update;
logic [ADDR_WIDTH-1:0] start_address;

always @( posedge clk ) begin
  if ( reset )
    current_state <= STATE_WAIT;
  else
    current_state <= next_state;
end

assign update_data_addr_out = update; 

logic address_gen_run;
logic address_gen_done;
logic conv_run_pipe0, conv_run_pipe1, conv_run;
logic clr_acc;
logic last_acc;
logic q3_valid;

assign fm_gen_addr_en = address_gen_run;
assign we_out = q3_valid;

localparam WINDOW_SIZE = KERNEL_WIDTH*KERNEL_HEIGHT;
logic [$clog2(WINDOW_SIZE):0] mac_count;

// handling clr_acc and last_acc signals
always @(posedge clk) begin
    if (reset)
        mac_count <= 0;
    else if (conv_run) begin
        if (mac_count == WINDOW_SIZE-1)
            mac_count <= 0;
        else
            mac_count <= mac_count + 1;
    end
end

assign clr_acc = (conv_run && mac_count == 0)? 1 : 0;
assign last_acc = (conv_run && mac_count == WINDOW_SIZE-1)? 1 : 0;

logic [ADDR_WIDTH-1:0] wraddr;
assign wr_addr_out = wraddr;

always@(posedge clk) begin
    if (reset) begin
	  conv_run_pipe1 <= 'b0;
	  conv_run <= 'b0;
	  wraddr <= 'b0;
    end
    else begin
	  conv_run_pipe1 <= conv_run_pipe0;
	  conv_run <= conv_run_pipe1;
	  if (q3_valid) wraddr <= wraddr +1;
	  else wraddr <= wraddr;
    end
end

always@(*) begin
  next_state = current_state;
  update = 'b0;
  done = 'b0;
  address_gen_run = 'b0;
  //clr_run = 'b0;
  conv_run_pipe0 = 'b0;
  case ( current_state )
    STATE_WAIT: begin
      if (run) begin
          next_state = STATE_STREAM_DATA;
		  
      end
    end
    STATE_STREAM_DATA: begin
        conv_run_pipe0 = 1;
        address_gen_run = 1;
        if (address_gen_done) begin
            next_state = STATE_UPDATE_WINDOW;
        end
    end
    STATE_UPDATE_WINDOW: begin
        update = 'b1;
        if (is_last_begin_addr) begin
          next_state = STATE_WAIT_FINISHED;
        end
        else next_state = STATE_UPDATE_WAIT;
    end
    STATE_UPDATE_WAIT: begin
        next_state = STATE_STREAM_DATA;
    end
	STATE_WAIT_FINISHED: begin
		if(q3_valid) begin
			next_state = STATE_FINISHED;
		end
	end
    STATE_FINISHED: begin
        done = 'b1;
        next_state = STATE_FINISHED;
    end
    default: next_state = STATE_WAIT;
  endcase 
end


// for testing
assign MAC_en = conv_run;
assign MAC_counter = mac_count;
assign clr_sig = clr_acc;
assign last_sig = last_acc; 

read_address_gen #(
	.PARTITION_SIZE(KERNEL_WIDTH),
	.PARTITION_HEIGHT(KERNEL_HEIGHT),
	.ARRAY_SIZE(KERNEL_WIDTH*KERNEL_HEIGHT),
	.ARRAY_HEIGHT(KERNEL_HEIGHT),
	.ARRAY_WIDTH(KERNEL_WIDTH)
) weightReadAddressGen
( .clk(clk), 
  .run(address_gen_run),
  .begin_addr('d0),
  .addr_out(wt_read_addr_out),
   .wr_addr(),
  .done(address_gen_done)
  );

INT8_MAC_pipelined #( 
.M0_WIDTH(M0_WIDTH),
.CHANNEL_PAR(CHANNEL_PAR)) MAC_core(
 .CLK (clk), .RST(reset),
 .Qa_in(q_data_in), .Qw_in(q_weight_in),
 .Za_in(Z_data_in), .Zw_in(Z_weight_in), .Zo_in(Zo_in),
 .En_in(conv_run),
 .M0_in(M0_in), .n_in(n_in), .bias_in(bias_in),
 .clear_in(clr_acc), .last_in(last_acc),
 .Q3_out(q_out), .Q3_valid_out(q3_valid)
);


endmodule