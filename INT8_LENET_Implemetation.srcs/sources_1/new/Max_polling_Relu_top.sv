`timescale 1ns / 1ps

module MaxPooling_Relu_top #(
 parameter KERNEL_WIDTH = 2,
 parameter KERNEL_HEIGHT = 2,
 parameter FM_WIDTH = 26,
 parameter FM_HEIGHT = 26,
 parameter DATA_WIDTH = 8,
 parameter ADDR_WIDTH = 10
)
(
input logic clk, run, reset,
input logic signed [DATA_WIDTH -1: 0] data_in,
input logic signed [DATA_WIDTH -1:0] Zo_in,
output logic [ADDR_WIDTH-1: 0] read_data_address,
output logic signed [DATA_WIDTH -1: 0] result_out,
output logic [ADDR_WIDTH-1: 0] w_address_out,
output logic we_out,
output logic done
);

typedef enum
{ STATE_IDLE,
  STATE_STREAM_DATA,
  STATE_UPDATE_WINDOW,
  STATE_UPDATE_WAIT,
  STATE_WAIT_FINISHED,
  STATE_FINISHED
  } states;
states state_reg, state_next;

logic update;
logic max_run, max_run_pipe0, max_run_pipe1;
logic address_gen_run;  
logic w_en, w_en_pipe0, w_en_pipe1;
assign we_out = w_en;

always_ff @(posedge clk) begin
    if(reset) begin
        state_reg <= STATE_IDLE;
         max_run <= 'b0;
         max_run_pipe1 <= 'b0;
         w_en <= 'b0;
         w_en_pipe1 <= 'b0;
    end
    else begin
        state_reg <= state_next;
        max_run_pipe1 <= max_run_pipe0;
        max_run <= max_run_pipe1;
        w_en_pipe1 <= w_en_pipe0;
        w_en <= w_en_pipe1;
    end 
end 

logic [FM_WIDTH-1: 0] col_count = 'd0;
logic [FM_HEIGHT-1: 0] row_count = 'd0;

logic is_last_addr;
logic [ADDR_WIDTH-1:0] begin_read_addr = 'd0;

assign is_last_addr = ((col_count == FM_WIDTH - KERNEL_WIDTH)||(col_count == FM_WIDTH - KERNEL_WIDTH -1)) && 
((row_count == FM_HEIGHT - KERNEL_HEIGHT)||(row_count == FM_HEIGHT - KERNEL_HEIGHT-1));

logic address_gen_done;

always_ff @(posedge clk) begin
    if(reset) begin
        col_count <= 'd0;
        row_count <= 'd0;
    end 
    else if (update) begin
        col_count <= ((col_count + 2 < FM_WIDTH - KERNEL_WIDTH)||(col_count + 2 == FM_WIDTH - KERNEL_WIDTH))? col_count +'d2: 'd0;
        row_count <= (is_last_addr)? 'd0: ((col_count == FM_WIDTH - KERNEL_WIDTH)||(col_count== FM_WIDTH - KERNEL_WIDTH -1))? row_count + 'd2: row_count;
    end
end
always_ff @(posedge clk) begin
    if(reset) begin
        begin_read_addr  <= 'd0;
    end
    else if (update) begin
        if(done) begin
            begin_read_addr <= 'd0;
        end
        else if (col_count == FM_WIDTH - KERNEL_WIDTH) begin
            begin_read_addr <= begin_read_addr + 'd2 + FM_WIDTH;
        end
        else if (col_count == FM_WIDTH - KERNEL_WIDTH -1) begin
            begin_read_addr <= begin_read_addr + 'd3 + FM_WIDTH;
        end
        else begin_read_addr <= begin_read_addr + 'd2;
    end
end


////////////FSM controller///////////
always_comb begin
    state_next = state_reg;
    update = 'b0;
    max_run_pipe0 = 'b0;
    address_gen_run = 'b0;
    w_en_pipe0 = 'b0;
    done = 'b0;
    
    case(state_reg) 
        
        STATE_IDLE: begin
            if(run) state_next = STATE_STREAM_DATA;
        end 
        
        STATE_STREAM_DATA: begin
            address_gen_run = 'b1;
            max_run_pipe0 = 'b1;
            if (address_gen_done) begin
                state_next = STATE_UPDATE_WINDOW;
            end
        end 
        
        STATE_UPDATE_WINDOW: begin
            w_en_pipe0 = 'b1;
            update = 'b1;
            if (is_last_addr)
                state_next = STATE_WAIT_FINISHED;
            else state_next = STATE_UPDATE_WAIT;
        end 
        
        STATE_UPDATE_WAIT: begin
            state_next = STATE_STREAM_DATA;
        end
        STATE_WAIT_FINISHED: begin
            state_next = STATE_FINISHED;
        end 
        STATE_FINISHED: begin
            done = 'b1;
            state_next = STATE_FINISHED;
        end
        default: state_next = STATE_IDLE;
    endcase
end

////////////DATAPATH/////////////
read_address_gen #(
	.PARTITION_SIZE(KERNEL_WIDTH),
	.PARTITION_HEIGHT(KERNEL_HEIGHT),
	.ARRAY_SIZE(FM_HEIGHT*FM_WIDTH),
	.ARRAY_HEIGHT(FM_HEIGHT),
	.ARRAY_WIDTH(FM_WIDTH)
) BufferReadAddressGen
( .clk(clk), 
  .run(address_gen_run),
  .begin_addr(begin_read_addr),
  .addr_out(read_data_address),
   .wr_addr(),
  .done(address_gen_done)
 );
 
 Maxpooling2x2_Relu #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
 ) max_relu
 (
    .run(max_run),
    .clk(clk),
    .reset(reset),
    .data_in(data_in),
    .Zo_in(Zo_in),
    .clear(w_en),
    .result_out(result_out),
    .address_out(w_address_out)
 );


endmodule
