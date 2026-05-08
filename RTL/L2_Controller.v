`timescale 1ns / 1ps
// =============================================================================
// Author      : Khanh
// Title       : L2_Controller
// Description : Layer-2 controller for the LeNet pipeline. It reads L1 pooled
//               outputs, schedules the second convolution stage, and manages
//               shared-engine execution and completion detection.
// =============================================================================
module L2_Controller #(
    parameter DATA_WIDTH    = 8,
    parameter ADDR_WIDTH    = 10,
    parameter M0_WIDTH      = 32,
    parameter CHANNEL_PAR   = 6,
    parameter NUM_LANES     = 16,
    parameter CONV_KW       = 3,
    parameter CONV_KH       = 3,
    parameter CONV_FM_W     = 13,
    parameter CONV_FM_H     = 13,
    parameter CONV_RES_W    = 11,
    parameter CONV_RES_H    = 11,
    parameter WEIGHT_MEMFILE_B0 = "layer2_weights_b0.mem",
    parameter WEIGHT_MEMFILE_B1 = "layer2_weights_b1.mem",
    parameter WEIGHT_MEMFILE_B2 = "layer2_weights_b2.mem",
    parameter WEIGHT_MEMFILE_B3 = "layer2_weights_b3.mem"
)(
    input  wire clk,
    input  wire reset,
    input  wire run,

    input  wire [NUM_LANES*DATA_WIDTH-1:0] l1_mem_data,
    output wire [ADDR_WIDTH-1:0]           l1_rd_addr,
    output wire                            l1_rd_en,

    input  wire [NUM_LANES-1:0] pool_done,

    output wire [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] Qa_bus,
    output wire signed [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] Qw_bus,
    output wire [NUM_LANES*DATA_WIDTH-1:0]             Za_bus,
    output wire signed [NUM_LANES*DATA_WIDTH-1:0]      Zw_bus,
    output wire [NUM_LANES*DATA_WIDTH-1:0]             Zo_bus,
    output wire signed [NUM_LANES*M0_WIDTH-1:0]        M0_bus,
    output wire [NUM_LANES*6-1:0]                      n_bus,
    output wire signed [NUM_LANES*32-1:0]              bias_bus,

    output wire [NUM_LANES-1:0] lane_active_mask,
    output wire [NUM_LANES-1:0] pool_bypass,
    output wire [NUM_LANES*5-1:0] pool_fm_width_bus,
    output wire [NUM_LANES*5-1:0] pool_fm_height_bus,

    output wire En_in,
    output wire clear_in,
    output wire last_in,

    output wire done
);


localparam [7:0] ZA = 8'd57;  
localparam signed [7:0] ZW = 8'sd0;

wire [7:0]  Zo_f [0:15];
wire [31:0] M0_f [0:15];
wire [5:0]  n_f  [0:15];
wire signed [31:0] bias_f [0:15];

genvar gq;
generate
for (gq = 0; gq < 16; gq = gq + 1) begin : QPARAMS
    assign Zo_f[gq]   = 8'd75;
end
endgenerate

assign M0_f[0] = 32'd1551900460; assign n_f[0] = 6'd9;  assign bias_f[0] = 32'd22;
assign M0_f[1] = 32'd1144523593; assign n_f[1] = 6'd9;  assign bias_f[1] = -32'd242;
assign M0_f[2] = 32'd1196926085; assign n_f[2] = 6'd9;  assign bias_f[2] = 32'd21;
assign M0_f[3] = 32'd1578201076; assign n_f[3] = 6'd9;  assign bias_f[3] = 32'd108;
assign M0_f[4] = 32'd1364643341; assign n_f[4] = 6'd9;  assign bias_f[4] = 32'd386;
assign M0_f[5] = 32'd1094120377; assign n_f[5] = 6'd9;  assign bias_f[5] = 32'd590;
assign M0_f[6] = 32'd1268637780; assign n_f[6] = 6'd9;  assign bias_f[6] = 32'd303;
assign M0_f[7] = 32'd1273330442; assign n_f[7] = 6'd9;  assign bias_f[7] = -32'd82;
assign M0_f[8] = 32'd1167884266; assign n_f[8] = 6'd9;  assign bias_f[8] = 32'd297;
assign M0_f[9] = 32'd1267679077; assign n_f[9] = 6'd9;  assign bias_f[9] = 32'd297;
assign M0_f[10] = 32'd1898435994; assign n_f[10] = 6'd10;  assign bias_f[10] = -32'd232;
assign M0_f[11] = 32'd1400639079; assign n_f[11] = 6'd9;  assign bias_f[11] = -32'd151;
assign M0_f[12] = 32'd1089299928; assign n_f[12] = 6'd9;  assign bias_f[12] = -32'd419;
assign M0_f[13] = 32'd1258529990; assign n_f[13] = 6'd9;  assign bias_f[13] = -32'd716;
assign M0_f[14] = 32'd1327363084; assign n_f[14] = 6'd9;  assign bias_f[14] = -32'd266;
assign M0_f[15] = 32'd1436180619; assign n_f[15] = 6'd9;  assign bias_f[15] = 32'd630;

// -----------------------------------------------------------------------
// Weight ROM banks
// 4 banks × 9 entries × (4 filters × 6 channels × 8-bit) = 192b / entry
// -----------------------------------------------------------------------
reg [4*CHANNEL_PAR*DATA_WIDTH-1:0] wrom_b0 [0:CONV_KW*CONV_KH-1];
reg [4*CHANNEL_PAR*DATA_WIDTH-1:0] wrom_b1 [0:CONV_KW*CONV_KH-1];
reg [4*CHANNEL_PAR*DATA_WIDTH-1:0] wrom_b2 [0:CONV_KW*CONV_KH-1];
reg [4*CHANNEL_PAR*DATA_WIDTH-1:0] wrom_b3 [0:CONV_KW*CONV_KH-1];

initial begin
    $readmemh(WEIGHT_MEMFILE_B0, wrom_b0);
    $readmemh(WEIGHT_MEMFILE_B1, wrom_b1);
    $readmemh(WEIGHT_MEMFILE_B2, wrom_b2);
    $readmemh(WEIGHT_MEMFILE_B3, wrom_b3);
end

// -----------------------------------------------------------------------
// FSM
// -----------------------------------------------------------------------
localparam S_IDLE        = 3'd0;
localparam S_STREAM      = 3'd1;
localparam S_FLUSH1      = 3'd2; // drain 1-cycle memory read latency
localparam S_UPDATE      = 3'd3;
localparam S_UPDATE_WAIT = 3'd4;
localparam S_WAIT_DONE   = 3'd5;
localparam S_DONE        = 3'd6;

reg [2:0] state;

reg [ADDR_WIDTH-1:0] col_cnt, row_cnt, begin_addr;

reg [3:0] issue_tap_cnt;

reg current_window_was_last;

wire is_last_window_cur;
assign is_last_window_cur = (col_cnt == CONV_RES_W - 1) && (row_cnt == CONV_RES_H - 1);


wire [1:0] issue_tap_col = issue_tap_cnt % CONV_KW;
wire [1:0] issue_tap_row = issue_tap_cnt / CONV_KW;

wire [4:0] issue_pix_row = row_cnt[4:0] + issue_tap_row;
wire [4:0] issue_pix_col = col_cnt[4:0] + issue_tap_col;

// Partition select:
//   0 -> even memories (rows 0..5)
//   1 -> odd  memories (rows 6..12)
wire issue_part_sel = (issue_pix_row >= 5'd6);

// Local memory row inside selected partition
wire [4:0] issue_local_row = issue_part_sel ? (issue_pix_row - 5'd6) : issue_pix_row;

// Local memory address within partition memory
wire [ADDR_WIDTH-1:0] issue_local_addr =
    issue_local_row * CONV_FM_W + issue_pix_col;

// rd_en only while issuing taps
wire issue_active = (state == S_STREAM);

assign l1_rd_addr = issue_active ? issue_local_addr : {ADDR_WIDTH{1'b0}};
assign l1_rd_en   = issue_active;

// -----------------------------------------------------------------------
// 1-stage metadata pipeline to align with Shared_Engine local memory latency
// -----------------------------------------------------------------------
reg        meta_vld_d0;
reg [3:0]  meta_tap_d0;
reg        meta_clear_d0;
reg        meta_last_d0;
reg        meta_part_d0;

// exec_* align with l1_mem_data of the same cycle
wire       exec_valid    = meta_vld_d0;
wire [3:0] exec_tap_cnt  = meta_tap_d0;
wire       exec_clear    = meta_clear_d0;
wire       exec_last     = meta_last_d0;
wire       exec_part_sel = meta_part_d0;

// MAC control must be combinational from exec_*.
// exec_* is already delayed to match l1_mem_data and Qw_bus/Qa_bus.
// Do NOT register these three signals again, otherwise MAC samples the wrong tap.
assign En_in    = exec_valid;
assign clear_in = exec_valid & exec_clear;
assign last_in  = exec_valid & exec_last;

//done pulse 1 cycle  
reg done_r;
assign done = done_r;

// -----------------------------------------------------------------------
// Sequential control
// -----------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        state                  <= S_IDLE;
        col_cnt                <= {ADDR_WIDTH{1'b0}};
        row_cnt                <= {ADDR_WIDTH{1'b0}};
        begin_addr             <= {ADDR_WIDTH{1'b0}};
        issue_tap_cnt          <= 4'd0;
        current_window_was_last<= 1'b0;

        meta_vld_d0            <= 1'b0;
        meta_tap_d0            <= 4'd0;
        meta_clear_d0          <= 1'b0;
        meta_last_d0           <= 1'b0;
        meta_part_d0           <= 1'b0;

        done_r                 <= 1'b0;
    end
    else begin
        // default pulse outputs
        done_r <= 1'b0;

        // default: no new issued metadata unless overridden in S_STREAM
        meta_vld_d0   <= 1'b0;
        meta_tap_d0   <= 4'd0;
        meta_clear_d0 <= 1'b0;
        meta_last_d0  <= 1'b0;
        meta_part_d0  <= 1'b0;

        case (state)
        S_IDLE: begin
            if (run) begin
                col_cnt                 <= {ADDR_WIDTH{1'b0}};
                row_cnt                 <= {ADDR_WIDTH{1'b0}};
                begin_addr              <= {ADDR_WIDTH{1'b0}};
                issue_tap_cnt           <= 4'd0;
                current_window_was_last <= 1'b0;

                meta_vld_d0             <= 1'b0;
                meta_tap_d0             <= 4'd0;
                meta_clear_d0           <= 1'b0;
                meta_last_d0            <= 1'b0;
                meta_part_d0            <= 1'b0;

                state                   <= S_STREAM;
            end
        end

        // ---------------------------------------------------------------
        // Issue 9 tap reads into Shared_Engine local memories
        // ---------------------------------------------------------------
        S_STREAM: begin
            meta_vld_d0   <= 1'b1;
            meta_tap_d0   <= issue_tap_cnt;
            meta_clear_d0 <= (issue_tap_cnt == 4'd0);
            meta_last_d0  <= (issue_tap_cnt == 4'd8);
            meta_part_d0  <= issue_part_sel;

            if (issue_tap_cnt == 4'd8) begin
                issue_tap_cnt <= 4'd0;
                state         <= S_FLUSH1;
            end
            else begin
                issue_tap_cnt <= issue_tap_cnt + 1'b1;
            end
        end

        S_FLUSH1: begin
            state <= S_UPDATE;
        end

        S_UPDATE: begin
            current_window_was_last <= is_last_window_cur;

            if (col_cnt < CONV_RES_W - 1) begin
                col_cnt    <= col_cnt + 1'b1;
                begin_addr <= begin_addr + 1'b1;
            end
            else begin
                col_cnt <= {ADDR_WIDTH{1'b0}};
                if (row_cnt < CONV_RES_H - 1) begin
                    row_cnt    <= row_cnt + 1'b1;
                    begin_addr <= begin_addr + CONV_KW; // 10 -> 13 on row wrap
                end
                else begin
                    row_cnt    <= {ADDR_WIDTH{1'b0}};
                    begin_addr <= {ADDR_WIDTH{1'b0}};
                end
            end

            state <= S_UPDATE_WAIT;
        end

        S_UPDATE_WAIT: begin
            if (current_window_was_last)
                state <= S_WAIT_DONE;
            else
                state <= S_STREAM;
        end
        S_WAIT_DONE: begin
            if (pool_done[0]) begin
                state  <= S_DONE;
                done_r <= 1'b1;
            end
        end

        S_DONE: begin
            state <= S_DONE; 
        end

        default: begin
            state <= S_IDLE;
        end
        endcase
    end
end

//debug
reg [ADDR_WIDTH-1:0] meta_addr_d0;
reg [4:0] meta_pix_row_d0;
reg [4:0] meta_pix_col_d0;

always @(posedge clk) begin
    if (reset) begin
        meta_addr_d0    <= 0;
        meta_pix_row_d0 <= 0;
        meta_pix_col_d0 <= 0;
    end
    else begin
        if (state == S_STREAM) begin
            meta_addr_d0    <= issue_local_addr;
            meta_pix_row_d0 <= issue_pix_row;
            meta_pix_col_d0 <= issue_pix_col;
        end
    end
end

// -----------------------------------------------------------------------
// Decode 12 L1 memories → 6 logic channels
// exec_part_sel chooses even or odd partition.
// -----------------------------------------------------------------------
wire [DATA_WIDTH-1:0] ch_pixel [0:5];

genvar gc;
generate
for (gc = 0; gc < 6; gc = gc + 1) begin : CH_DECODE
    wire [DATA_WIDTH-1:0] pix_even;
    wire [DATA_WIDTH-1:0] pix_odd;

    assign pix_even = l1_mem_data[(2*gc)*DATA_WIDTH +: DATA_WIDTH];
    assign pix_odd  = l1_mem_data[(2*gc+1)*DATA_WIDTH +: DATA_WIDTH];

    assign ch_pixel[gc] = exec_part_sel ? pix_odd : pix_even;
end
endgenerate

// -----------------------------------------------------------------------
// Qa_bus: broadcast same 6-channel input vector to all 16 output-filter lanes
// -----------------------------------------------------------------------
genvar gl, gch;
generate
for (gl = 0; gl < NUM_LANES; gl = gl + 1) begin : QA_LANE
    for (gch = 0; gch < CHANNEL_PAR; gch = gch + 1) begin : QA_CH
        assign Qa_bus[(gl*CHANNEL_PAR + gch)*DATA_WIDTH +: DATA_WIDTH] = ch_pixel[gch];
    end
end
endgenerate


wire [4*CHANNEL_PAR*DATA_WIDTH-1:0] wt_b0 = wrom_b0[exec_tap_cnt];
wire [4*CHANNEL_PAR*DATA_WIDTH-1:0] wt_b1 = wrom_b1[exec_tap_cnt];
wire [4*CHANNEL_PAR*DATA_WIDTH-1:0] wt_b2 = wrom_b2[exec_tap_cnt];
wire [4*CHANNEL_PAR*DATA_WIDTH-1:0] wt_b3 = wrom_b3[exec_tap_cnt];

genvar gf;
generate
for (gf = 0; gf < 4; gf = gf + 1) begin : QW_FILL
    assign Qw_bus[(0*4 + gf)*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
        wt_b0[gf*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH];

    assign Qw_bus[(1*4 + gf)*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
        wt_b1[gf*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH];

    assign Qw_bus[(2*4 + gf)*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
        wt_b2[gf*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH];

    assign Qw_bus[(3*4 + gf)*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
        wt_b3[gf*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH];
end
endgenerate


genvar gp;
generate
for (gp = 0; gp < NUM_LANES; gp = gp + 1) begin : PARAM_FILL
    assign Za_bus  [gp*DATA_WIDTH +: DATA_WIDTH] = ZA;
    assign Zw_bus  [gp*DATA_WIDTH +: DATA_WIDTH] = ZW;
    assign Zo_bus  [gp*DATA_WIDTH +: DATA_WIDTH] = Zo_f[gp];
    assign M0_bus  [gp*M0_WIDTH +: M0_WIDTH]     = $signed(M0_f[gp]);
    assign n_bus   [gp*6 +: 6]                   = n_f[gp];
    assign bias_bus[gp*32 +: 32]                 = bias_f[gp];
end
endgenerate


assign lane_active_mask   = {NUM_LANES{1'b1}};
assign pool_bypass        = {NUM_LANES{1'b0}};
assign pool_fm_width_bus  = {NUM_LANES{5'd11}};
assign pool_fm_height_bus = {NUM_LANES{5'd11}};


//assign done = (state == S_DONE);

endmodule
