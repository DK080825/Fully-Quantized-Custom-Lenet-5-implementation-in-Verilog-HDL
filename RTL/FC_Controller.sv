`timescale 1ns / 1ps

module FC_Controller #(
    parameter DATA_WIDTH    = 8,
    parameter ADDR_WIDTH    = 10,
    parameter M0_WIDTH      = 32,
    parameter CHANNEL_PAR   = 6,
    parameter NUM_LANES     = 16,
    parameter NUM_ACTIVE    = 10,
    parameter FC_INPUT_SIZE = 400,   // 5*5*16
    parameter L2_MEM_DEPTH  = 25,    // pooled 5*5 from each of 16 memories
    parameter STEPS_PER_RUN = 80,    // 400 / 5
    parameter WEIGHT_MEMFILE_B0 = "fc_weights_b0.mem",
    parameter WEIGHT_MEMFILE_B1 = "fc_weights_b1.mem",
    parameter WEIGHT_MEMFILE_B2 = "fc_weights_b2.mem",
    parameter WEIGHT_MEMFILE_B3 = "fc_weights_b3.mem",
    parameter WEIGHT_MEMFILE_B4 = "fc_weights_b4.mem"
)(
    input  wire clk,
    input  wire reset,
    input  wire run,

    input  wire [NUM_LANES*DATA_WIDTH-1:0] l2_mem_data,
    output wire [ADDR_WIDTH-1:0]           l2_rd_addr,
    output wire                            l2_rd_en,

    input  wire [NUM_LANES*DATA_WIDTH-1:0] mac_q3_out,
    input  wire [NUM_LANES-1:0]            mac_q3_valid,

    output reg  [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] Qa_bus,
    output wire signed [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] Qw_bus,
    output wire [NUM_LANES*DATA_WIDTH-1:0]                    Za_bus,
    output wire signed [NUM_LANES*DATA_WIDTH-1:0]             Zw_bus,
    output wire [NUM_LANES*DATA_WIDTH-1:0]                    Zo_bus,
    output wire signed [NUM_LANES*M0_WIDTH-1:0]               M0_bus,
    output wire [NUM_LANES*6-1:0]                             n_bus,
    output wire signed [NUM_LANES*32-1:0]                     bias_bus,

    output wire [NUM_LANES-1:0] lane_active_mask,
    output wire [NUM_LANES-1:0] pool_bypass,
    output wire [NUM_LANES*5-1:0] pool_fm_width_bus,
    output wire [NUM_LANES*5-1:0] pool_fm_height_bus,

    output wire En_in,
    output wire clear_in,
    output wire last_in,

    output wire [DATA_WIDTH-1:0] neuron_out [0:9],
    output wire done
);

// -----------------------------------------------------------------------
// Quantization parameters for 10 neurons
// -----------------------------------------------------------------------
localparam [7:0] ZA = 8'd75;
localparam signed [7:0] ZW = 8'sd0;

wire [7:0]  Zo_f [0:9];
wire [31:0] M0_f [0:9];
wire [5:0]  n_f  [0:9];
wire signed [31:0] bias_f [0:9];

assign Zo_f[0] = 8'd69; assign M0_f[0] = 32'd1798618152; assign n_f[0] = 6'd9; assign bias_f[0] =  32'sd133;
assign Zo_f[1] = 8'd69; assign M0_f[1] = 32'd1893381934; assign n_f[1] = 6'd9; assign bias_f[1] =  32'sd121;
assign Zo_f[2] = 8'd69; assign M0_f[2] = 32'd2011248985; assign n_f[2] = 6'd9; assign bias_f[2] = -32'sd40;
assign Zo_f[3] = 8'd69; assign M0_f[3] = 32'd1997046003; assign n_f[3] = 6'd9; assign bias_f[3] = -32'sd45;
assign Zo_f[4] = 8'd69; assign M0_f[4] = 32'd1604336325; assign n_f[4] = 6'd9; assign bias_f[4] = -32'sd26;
assign Zo_f[5] = 8'd69; assign M0_f[5] = 32'd1110916924; assign n_f[5] = 6'd8; assign bias_f[5] =  32'sd85;
assign Zo_f[6] = 8'd69; assign M0_f[6] = 32'd1812078817; assign n_f[6] = 6'd9; assign bias_f[6] = -32'sd73;
assign Zo_f[7] = 8'd69; assign M0_f[7] = 32'd1792013371; assign n_f[7] = 6'd9; assign bias_f[7] = -32'sd10;
assign Zo_f[8] = 8'd69; assign M0_f[8] = 32'd1090754087; assign n_f[8] = 6'd8; assign bias_f[8] =  32'sd20;
assign Zo_f[9] = 8'd69; assign M0_f[9] = 32'd1092942666; assign n_f[9] = 6'd8; assign bias_f[9] =  32'sd29;

// -----------------------------------------------------------------------
// Weight ROM banks: 5 banks × 80 entries × 10 neurons × 8-bit
// bank b, entry s -> weight for input index (s*5 + b) across 10 neurons
// -----------------------------------------------------------------------
reg [NUM_ACTIVE*DATA_WIDTH-1:0] wrom [0:4][0:STEPS_PER_RUN-1];
initial begin
    $readmemh(WEIGHT_MEMFILE_B0, wrom[0]);
    $readmemh(WEIGHT_MEMFILE_B1, wrom[1]);
    $readmemh(WEIGHT_MEMFILE_B2, wrom[2]);
    $readmemh(WEIGHT_MEMFILE_B3, wrom[3]);
    $readmemh(WEIGHT_MEMFILE_B4, wrom[4]);
end

// -----------------------------------------------------------------------
// Local flatten buffer for 400 FC inputs
// Flatten order is channel-major, matching PyTorch/NCHW flatten:
//   fc_act_buf[channel*25 + addr] = value from L2 memory lane channel at address addr
// -----------------------------------------------------------------------
reg [DATA_WIDTH-1:0] fc_act_buf [0:FC_INPUT_SIZE-1];
integer bi;
initial begin
    for (bi = 0; bi < FC_INPUT_SIZE; bi = bi + 1)
        fc_act_buf[bi] = {DATA_WIDTH{1'b0}};
end

// -----------------------------------------------------------------------
// FSM
// -----------------------------------------------------------------------
localparam S_IDLE       = 3'd0;
localparam S_READ_REQ   = 3'd1;   // issue read addresses 0..24
localparam S_READ_DRAIN = 3'd2;   // capture last returned beat
localparam S_STREAM     = 3'd3;   // 80 MAC cycles
localparam S_WAIT_DONE  = 3'd4;
localparam S_DONE       = 3'd5;

reg [2:0] state;


reg [4:0] rd_req_addr;
reg       rd_meta_vld_d0;
reg [4:0] rd_meta_addr_d0;


reg [6:0] step_cnt;
wire last_step = (step_cnt == STEPS_PER_RUN - 1);
wire stream_valid = (state == S_STREAM);

assign En_in    = stream_valid;
assign clear_in = stream_valid & (step_cnt == 7'd0);
assign last_in  = stream_valid & last_step;


assign l2_rd_addr = {{ADDR_WIDTH-5{1'b0}}, rd_req_addr};
assign l2_rd_en   = (state == S_READ_REQ);


integer cap_i;
always @(posedge clk) begin
    if (reset) begin
        rd_meta_vld_d0  <= 1'b0;
        rd_meta_addr_d0 <= 5'd0;
    end
    else begin
        // metadata pipeline for 1-cycle memory latency
        rd_meta_vld_d0  <= (state == S_READ_REQ);
        rd_meta_addr_d0 <= rd_req_addr;

        // capture returned beat
        if (rd_meta_vld_d0) begin
            for (cap_i = 0; cap_i < NUM_LANES; cap_i = cap_i + 1) begin
                // Channel-major flatten:
                //   flat_idx = channel * L2_MEM_DEPTH + spatial_addr
                // This matches PyTorch flatten on NCHW tensor [16][5][5].
                fc_act_buf[cap_i*L2_MEM_DEPTH + rd_meta_addr_d0]
                    <= l2_mem_data[cap_i*DATA_WIDTH +: DATA_WIDTH];
            end
        end
    end
end


reg done_r;
assign done = done_r;

always @(posedge clk) begin
    if (reset) begin
        state      <= S_IDLE;
        rd_req_addr<= 5'd0;
        step_cnt   <= 7'd0;

        done_r <= 1'b0;
    end
    else begin
        done_r <= 1'b0;  

        case (state)
        S_IDLE: begin
            rd_req_addr <= 5'd0;
            step_cnt    <= 7'd0;
            if (run)
                state <= S_READ_REQ;
        end

  
        S_READ_REQ: begin
            if (rd_req_addr == L2_MEM_DEPTH - 1) begin
                rd_req_addr <= 5'd0;
                state       <= S_READ_DRAIN;
            end
            else begin
                rd_req_addr <= rd_req_addr + 1'b1;
            end
        end


        S_READ_DRAIN: begin
            step_cnt <= 7'd0;
            state    <= S_STREAM;
        end


        S_STREAM: begin
            if (last_step) begin
                step_cnt <= 7'd0;
                state    <= S_WAIT_DONE;
            end
            else begin
                step_cnt <= step_cnt + 1'b1;
            end
        end

  
        S_WAIT_DONE: begin
            if (mac_q3_valid[0]) begin
                state <= S_DONE;
                done_r <= 1'b1;
            end
        end

        S_DONE: begin
            state <= S_DONE;   // keep one-shot behavior for now
        end

        default: begin
            state <= S_IDLE;
        end
        endcase
    end
end


wire [8:0] base_idx = step_cnt * 5;

wire [DATA_WIDTH-1:0] act0 = fc_act_buf[base_idx + 0];
wire [DATA_WIDTH-1:0] act1 = fc_act_buf[base_idx + 1];
wire [DATA_WIDTH-1:0] act2 = fc_act_buf[base_idx + 2];
wire [DATA_WIDTH-1:0] act3 = fc_act_buf[base_idx + 3];
wire [DATA_WIDTH-1:0] act4 = fc_act_buf[base_idx + 4];

integer ql;
always @(*) begin
    Qa_bus = {NUM_LANES*CHANNEL_PAR*DATA_WIDTH{1'b0}};

    for (ql = 0; ql < NUM_ACTIVE; ql = ql + 1) begin
        Qa_bus[ql*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
            { 8'd0,   // ch5 masked
              act4,   // ch4
              act3,   // ch3
              act2,   // ch2
              act1,   // ch1
              act0 }; // ch0
    end
end


genvar gn;
generate
for (gn = 0; gn < NUM_ACTIVE; gn = gn + 1) begin : QW_LANE
    assign Qw_bus[gn*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
        {
            8'd0,  // ch5 masked
            wrom[4][step_cnt][gn*DATA_WIDTH +: DATA_WIDTH], // ch4
            wrom[3][step_cnt][gn*DATA_WIDTH +: DATA_WIDTH], // ch3
            wrom[2][step_cnt][gn*DATA_WIDTH +: DATA_WIDTH], // ch2
            wrom[1][step_cnt][gn*DATA_WIDTH +: DATA_WIDTH], // ch1
            wrom[0][step_cnt][gn*DATA_WIDTH +: DATA_WIDTH]  // ch0
        };
end

assign Qw_bus[NUM_ACTIVE*CHANNEL_PAR*DATA_WIDTH +:
              (NUM_LANES-NUM_ACTIVE)*CHANNEL_PAR*DATA_WIDTH] =
       {((NUM_LANES-NUM_ACTIVE)*CHANNEL_PAR*DATA_WIDTH){1'b0}};
endgenerate


genvar gp;
generate
for (gp = 0; gp < NUM_ACTIVE; gp = gp + 1) begin : PARAMS
    assign Za_bus  [gp*DATA_WIDTH +: DATA_WIDTH] = ZA;
    assign Zw_bus  [gp*DATA_WIDTH +: DATA_WIDTH] = ZW;
    assign Zo_bus  [gp*DATA_WIDTH +: DATA_WIDTH] = Zo_f[gp];
    assign M0_bus  [gp*M0_WIDTH +: M0_WIDTH]     = $signed(M0_f[gp]);
    assign n_bus   [gp*6 +: 6]                   = n_f[gp];
    assign bias_bus[gp*32 +: 32]                 = bias_f[gp];
end

assign Za_bus  [NUM_ACTIVE*DATA_WIDTH +: (NUM_LANES-NUM_ACTIVE)*DATA_WIDTH] =
    {((NUM_LANES-NUM_ACTIVE)*DATA_WIDTH){1'b0}};
assign Zw_bus  [NUM_ACTIVE*DATA_WIDTH +: (NUM_LANES-NUM_ACTIVE)*DATA_WIDTH] =
    {((NUM_LANES-NUM_ACTIVE)*DATA_WIDTH){1'b0}};
assign Zo_bus  [NUM_ACTIVE*DATA_WIDTH +: (NUM_LANES-NUM_ACTIVE)*DATA_WIDTH] =
    {((NUM_LANES-NUM_ACTIVE)*DATA_WIDTH){1'b0}};
assign M0_bus  [NUM_ACTIVE*M0_WIDTH +: (NUM_LANES-NUM_ACTIVE)*M0_WIDTH] =
    {((NUM_LANES-NUM_ACTIVE)*M0_WIDTH){1'b0}};
assign n_bus   [NUM_ACTIVE*6 +: (NUM_LANES-NUM_ACTIVE)*6] =
    {((NUM_LANES-NUM_ACTIVE)*6){1'b0}};
assign bias_bus[NUM_ACTIVE*32 +: (NUM_LANES-NUM_ACTIVE)*32] =
    {((NUM_LANES-NUM_ACTIVE)*32){1'b0}};
endgenerate

// -----------------------------------------------------------------------
// Engine control constants for FC
// -----------------------------------------------------------------------
assign lane_active_mask   = {{(NUM_LANES-NUM_ACTIVE){1'b0}}, {NUM_ACTIVE{1'b1}}};
assign pool_bypass        = {NUM_LANES{1'b1}};
assign pool_fm_width_bus  = {NUM_LANES*5{1'b0}};
assign pool_fm_height_bus = {NUM_LANES*5{1'b0}};

// -----------------------------------------------------------------------
// Outputs to argmax / classifier
// -----------------------------------------------------------------------
genvar gout;
generate
for (gout = 0; gout < 10; gout = gout + 1) begin : NEURON_OUT
    assign neuron_out[gout] = mac_q3_out[gout*DATA_WIDTH +: DATA_WIDTH];
end
endgenerate

//assign done = (state == S_DONE);

endmodule