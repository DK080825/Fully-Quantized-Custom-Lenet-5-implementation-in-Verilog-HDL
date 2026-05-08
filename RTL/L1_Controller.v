`timescale 1ns / 1ps
// =============================================================================
// Author      : Khanh
// Title       : L1_Controller
// Description : Layer-1 controller for the LeNet pipeline. It streams 3x3
//               windows from the input banks, aligns memory latency, and
//               drives the shared engine for convolution and pooling.
// =============================================================================
module L1_Controller #(
    parameter DATA_WIDTH         = 8,
    parameter ADDR_WIDTH         = 10,
    parameter M0_WIDTH           = 32,
    parameter CHANNEL_PAR        = 6,
    parameter NUM_LANES          = 16,
    parameter CONV_KW            = 3,
    parameter CONV_KH            = 3,
    parameter IMAGE_BANK1_WIDTH  = 28,
    parameter IMAGE_BANK1_HEIGHT = 14,
    parameter IMAGE_BANK2_WIDTH  = 28,
    parameter IMAGE_BANK2_HEIGHT = 16,
    parameter CONV_RES1_W        = 26,
    parameter CONV_RES1_H        = 12,
    parameter CONV_RES2_W        = 26,
    parameter CONV_RES2_H        = 14,
    parameter WEIGHT_MEMFILE     = "layer1_weights_lutram.mem"
)(
    input  wire clk,
    input  wire reset,
    input  wire run,              // one-cycle pulse to start

    input  wire [DATA_WIDTH-1:0] fm_data_in0,   // bank1 pixel (2-cycle latency)
    input  wire [DATA_WIDTH-1:0] fm_data_in1,   // bank2 pixel (2-cycle latency)
    output wire [ADDR_WIDTH-1:0] fm_read_addr0,
    output wire [ADDR_WIDTH-1:0] fm_read_addr1,

    // Pool done from engine (bit per lane)
    input  wire [NUM_LANES-1:0] pool_done,

    // Outputs to Shared_Engine
    output reg  [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] Qa_bus,
    output wire signed [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] Qw_bus,
    output wire [NUM_LANES*DATA_WIDTH-1:0] Za_bus,
    output wire signed [NUM_LANES*DATA_WIDTH-1:0] Zw_bus,
    output wire [NUM_LANES*DATA_WIDTH-1:0] Zo_bus,
    output wire signed [NUM_LANES*M0_WIDTH-1:0] M0_bus,
    output wire [NUM_LANES*6-1:0]               n_bus,
    output wire signed [NUM_LANES*32-1:0]       bias_bus,

    output wire [NUM_LANES-1:0] lane_active_mask,
    output wire [NUM_LANES-1:0] pool_bypass,
    output wire [NUM_LANES*5-1:0] pool_fm_width_bus,
    output wire [NUM_LANES*5-1:0] pool_fm_height_bus,

    output wire En_in,
    output wire clear_in,
    output wire last_in,

    output wire done
);

reg [2:0] state;
// -----------------------------------------------------------------------
// FSM
// -----------------------------------------------------------------------
localparam S_IDLE        = 3'd0;
localparam S_STREAM      = 3'd1;  // issue 9 tap addresses
localparam S_FLUSH1      = 3'd2;  // drain pipeline stage 1
localparam S_FLUSH2      = 3'd3;  // drain pipeline stage 2
localparam S_UPDATE      = 3'd4;
localparam S_UPDATE_WAIT = 3'd5;
localparam S_WAIT_DONE   = 3'd6;
localparam S_DONE        = 3'd7;

localparam [7:0] ZA = 8'd0;
localparam signed [7:0] ZW = 8'sd0;

// -----------------------------------------------------------------------
// Quantization parameters (real values provided by user)
// -----------------------------------------------------------------------
wire [7:0] Zo_f [0:5];
wire [31:0] M0_f [0:5];
wire [5:0] n_f [0:5];
wire signed [31:0] bias_f [0:5];

assign Zo_f[0]   = 8'd57; assign M0_f[0] = 32'd1086523253; assign n_f[0] = 6'd9;  assign bias_f[0] = -32'sd32;
assign Zo_f[1]   = 8'd57; assign M0_f[1] = 32'd1885069464; assign n_f[1] = 6'd10; assign bias_f[1] =  32'sd625;
assign Zo_f[2]   = 8'd57; assign M0_f[2] = 32'd1385459822; assign n_f[2] = 6'd9;  assign bias_f[2] =  32'sd2600;
assign Zo_f[3]   = 8'd57; assign M0_f[3] = 32'd1166647221; assign n_f[3] = 6'd9;  assign bias_f[3] =  32'sd8378;
assign Zo_f[4]   = 8'd57; assign M0_f[4] = 32'd1304869489; assign n_f[4] = 6'd9;  assign bias_f[4] =  32'sd2979;
assign Zo_f[5]   = 8'd57; assign M0_f[5] = 32'd1662666692; assign n_f[5] = 6'd10; assign bias_f[5] =  32'sd5254;

// -----------------------------------------------------------------------
// Weight ROM: 9 entries × (6 filters × 8-bit) = 48-bit / entry
// Entry layout: {filter5, filter4, ..., filter0}
// -----------------------------------------------------------------------
reg signed [6*DATA_WIDTH-1:0] weight_rom [0:CONV_KW*CONV_KH-1];
initial $readmemh(WEIGHT_MEMFILE, weight_rom);


// Window position counters for bank1 / bank2
reg [ADDR_WIDTH-1:0] col0, row0, begin_addr0;
reg [ADDR_WIDTH-1:0] col1, row1, begin_addr1;

wire is_last0_cur = (col0 == CONV_RES1_W - 1) && (row0 == CONV_RES1_H - 1);
wire is_last1_cur = (col1 == CONV_RES2_W - 1) && (row1 == CONV_RES2_H - 1);

reg  [3:0] issue_tap_cnt;
wire [1:0] issue_tap_col = issue_tap_cnt % CONV_KW;
wire [1:0] issue_tap_row = issue_tap_cnt / CONV_KW;

wire [ADDR_WIDTH-1:0] bank1_rd_addr_issue =
    begin_addr0 + issue_tap_row * IMAGE_BANK1_WIDTH + issue_tap_col;
wire [ADDR_WIDTH-1:0] bank2_rd_addr_issue =
    begin_addr1 + issue_tap_row * IMAGE_BANK2_WIDTH + issue_tap_col;

// During non-issue states, freeze addresses to 0 to reduce unnecessary toggling
reg bank1_finished;
reg bank2_window_was_last;

wire issue_active = (state == S_STREAM);
assign fm_read_addr0 = (issue_active && !bank1_finished) ? bank1_rd_addr_issue : {ADDR_WIDTH{1'b0}};
assign fm_read_addr1 = (issue_active) ? bank2_rd_addr_issue : {ADDR_WIDTH{1'b0}};


// 2-stage metadata pipeline to align with M10K 2-cycle data latency
reg        meta_vld_d0,   meta_vld_d1;
reg [3:0]  meta_tap_d0,   meta_tap_d1;
reg        meta_clear_d0, meta_clear_d1;
reg        meta_last_d0,  meta_last_d1;

// Pipeline metadata aligned to the 2-cycle M10K latency.
reg [ADDR_WIDTH-1:0] meta_row0_d0, meta_row0_d1;
reg [ADDR_WIDTH-1:0] meta_col0_d0, meta_col0_d1;
reg [ADDR_WIDTH-1:0] meta_row1_d0, meta_row1_d1;
reg [ADDR_WIDTH-1:0] meta_col1_d0, meta_col1_d1;
reg [ADDR_WIDTH-1:0] meta_addr0_d0, meta_addr0_d1;
reg [ADDR_WIDTH-1:0] meta_addr1_d0, meta_addr1_d1;

wire       exec_valid   = meta_vld_d1;
wire [3:0] exec_tap_cnt = meta_tap_d1;
wire       exec_clear   = meta_clear_d1;
wire       exec_last    = meta_last_d1;

assign En_in    = exec_valid;
assign clear_in = exec_valid & exec_clear;
assign last_in  = exec_valid & exec_last;

reg done_r;
assign done = done_r;

reg pool_done1_d;
wire pool_done1_pulse = pool_done[1] & ~pool_done1_d;

// -----------------------------------------------------------------------
// Sequential control
// -----------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        state                <= S_IDLE;

        issue_tap_cnt        <= 4'd0;

        meta_vld_d0          <= 1'b0;
        meta_vld_d1          <= 1'b0;
        meta_tap_d0          <= 4'd0;
        meta_tap_d1          <= 4'd0;
        meta_clear_d0        <= 1'b0;
        meta_clear_d1        <= 1'b0;
        meta_last_d0         <= 1'b0;
        meta_last_d1         <= 1'b0;

        // Debug metadata
        meta_row0_d0 <= {ADDR_WIDTH{1'b0}};
        meta_col0_d0 <= {ADDR_WIDTH{1'b0}};
        meta_row1_d0 <= {ADDR_WIDTH{1'b0}};
        meta_col1_d0 <= {ADDR_WIDTH{1'b0}};
        meta_row0_d1 <= {ADDR_WIDTH{1'b0}};
        meta_col0_d1 <= {ADDR_WIDTH{1'b0}};
        meta_row1_d1 <= {ADDR_WIDTH{1'b0}};
        meta_col1_d1 <= {ADDR_WIDTH{1'b0}};

        meta_addr0_d0 <= {ADDR_WIDTH{1'b0}};
        meta_addr0_d1 <= {ADDR_WIDTH{1'b0}};
        meta_addr1_d0 <= {ADDR_WIDTH{1'b0}};
        meta_addr1_d1 <= {ADDR_WIDTH{1'b0}};

        col0                 <= {ADDR_WIDTH{1'b0}};
        row0                 <= {ADDR_WIDTH{1'b0}};
        begin_addr0          <= {ADDR_WIDTH{1'b0}};
        col1                 <= {ADDR_WIDTH{1'b0}};
        row1                 <= {ADDR_WIDTH{1'b0}};
        begin_addr1          <= {ADDR_WIDTH{1'b0}};

        bank1_finished       <= 1'b0;
        bank2_window_was_last<= 1'b0;

        done_r               <= 1'b0;
        pool_done1_d         <= 1'b0;
    end
    else begin
        // default pulse outputs
        done_r <= 1'b0;  

        // delay pool_done[1] by 1 cycle for clean completion alignment
        pool_done1_d <= pool_done[1];

        // default: no new metadata issued unless overridden in S_STREAM
        meta_vld_d1   <= meta_vld_d0;
        meta_tap_d1   <= meta_tap_d0;
        meta_clear_d1 <= meta_clear_d0;
        meta_last_d1  <= meta_last_d0;

        meta_vld_d0   <= 1'b0;
        meta_tap_d0   <= 4'd0;
        meta_clear_d0 <= 1'b0;
        meta_last_d0  <= 1'b0;

        // Debug metadata
        meta_row0_d0 <= {ADDR_WIDTH{1'b0}};
        meta_col0_d0 <= {ADDR_WIDTH{1'b0}};
        meta_row1_d0 <= {ADDR_WIDTH{1'b0}};
        meta_col1_d0 <= {ADDR_WIDTH{1'b0}};

        meta_addr0_d0 <= {ADDR_WIDTH{1'b0}};
        meta_addr1_d0 <= {ADDR_WIDTH{1'b0}};

        meta_row0_d1 <= meta_row0_d0;
        meta_col0_d1 <= meta_col0_d0;
        meta_row1_d1 <= meta_row1_d0;
        meta_col1_d1 <= meta_col1_d0;

        meta_addr0_d1 <= meta_addr0_d0;
        meta_addr1_d1 <= meta_addr1_d0;

        case (state)
        // ---------------------------------------------------------------
        // Wait for start pulse
        // ---------------------------------------------------------------
        S_IDLE: begin
            if (run) begin
                issue_tap_cnt         <= 4'd0;

                meta_vld_d0           <= 1'b0;
                meta_vld_d1           <= 1'b0;
                meta_tap_d0           <= 4'd0;
                meta_tap_d1           <= 4'd0;
                meta_clear_d0         <= 1'b0;
                meta_clear_d1         <= 1'b0;
                meta_last_d0          <= 1'b0;
                meta_last_d1          <= 1'b0;

                // Debug metadata
                meta_row0_d0 <= {ADDR_WIDTH{1'b0}};
                meta_col0_d0 <= {ADDR_WIDTH{1'b0}};
                meta_row1_d0 <= {ADDR_WIDTH{1'b0}};
                meta_col1_d0 <= {ADDR_WIDTH{1'b0}};
                meta_row0_d1 <= {ADDR_WIDTH{1'b0}};
                meta_col0_d1 <= {ADDR_WIDTH{1'b0}};
                meta_row1_d1 <= {ADDR_WIDTH{1'b0}};
                meta_col1_d1 <= {ADDR_WIDTH{1'b0}};

                meta_addr0_d0 <= {ADDR_WIDTH{1'b0}};
                meta_addr0_d1 <= {ADDR_WIDTH{1'b0}};
                meta_addr1_d0 <= {ADDR_WIDTH{1'b0}};
                meta_addr1_d1 <= {ADDR_WIDTH{1'b0}};

                col0                  <= {ADDR_WIDTH{1'b0}};
                row0                  <= {ADDR_WIDTH{1'b0}};
                begin_addr0           <= {ADDR_WIDTH{1'b0}};
                col1                  <= {ADDR_WIDTH{1'b0}};
                row1                  <= {ADDR_WIDTH{1'b0}};
                begin_addr1           <= {ADDR_WIDTH{1'b0}};

                bank1_finished        <= 1'b0;
                bank2_window_was_last <= 1'b0;

                state                 <= S_STREAM;
            end
        end

        // ---------------------------------------------------------------
        // Issue 9 tap addresses into M10K
        // M10K data appears 2 cycles later, aligned with exec_* signals
        // ---------------------------------------------------------------
        S_STREAM: begin
            meta_vld_d0   <= 1'b1;
            meta_tap_d0   <= issue_tap_cnt;
            meta_clear_d0 <= (issue_tap_cnt == 4'd0);
            meta_last_d0  <= (issue_tap_cnt == 4'd8);

            // Capture current convolution window coordinate.
            // These coordinates will be delayed 2 cycles together with tap metadata.
            meta_row0_d0 <= row0;
            meta_col0_d0 <= col0;
            meta_row1_d0 <= row1;
            meta_col1_d0 <= col1;

            // Capture actual read addresses that are sent to the input banks.
            // These addresses will be delayed 2 cycles together with tap metadata.
            meta_addr0_d0 <= fm_read_addr0;
            meta_addr1_d0 <= fm_read_addr1;

            if (issue_tap_cnt == 4'd8) begin
                issue_tap_cnt <= 4'd0;
                state         <= S_FLUSH1;
            end
            else begin
                issue_tap_cnt <= issue_tap_cnt + 1'b1;
            end
        end

        // ---------------------------------------------------------------
        // Drain 2-cycle input pipeline after last issued tap
        // ---------------------------------------------------------------
        S_FLUSH1: begin
            state <= S_FLUSH2;
        end

        S_FLUSH2: begin
            state <= S_UPDATE;
        end

        // ---------------------------------------------------------------
        // Update to next window
        // IMPORTANT: latch whether CURRENT bank2 window is the last one
        // BEFORE modifying row1/col1/begin_addr1
        // ---------------------------------------------------------------
        S_UPDATE: begin
            bank2_window_was_last <= is_last1_cur;

            // Bank1 advance only until its own last window
            if (!bank1_finished) begin
                if (col0 < CONV_RES1_W - 1) begin
                    col0        <= col0 + 1'b1;
                    begin_addr0 <= begin_addr0 + 1'b1;
                end
                else begin
                    col0 <= {ADDR_WIDTH{1'b0}};
                    if (row0 < CONV_RES1_H - 1) begin
                        row0        <= row0 + 1'b1;
                        begin_addr0 <= begin_addr0 + CONV_KW;
                    end
                    else begin
                        row0           <= {ADDR_WIDTH{1'b0}};
                        begin_addr0    <= {ADDR_WIDTH{1'b0}};
                        bank1_finished <= 1'b1;
                    end
                end
            end

            // Bank2 advance
            if (col1 < CONV_RES2_W - 1) begin
                col1        <= col1 + 1'b1;
                begin_addr1 <= begin_addr1 + 1'b1;
            end
            else begin
                col1 <= {ADDR_WIDTH{1'b0}};
                if (row1 < CONV_RES2_H - 1) begin
                    row1        <= row1 + 1'b1;
                    begin_addr1 <= begin_addr1 + CONV_KW;
                end
                else begin
                    row1        <= {ADDR_WIDTH{1'b0}};
                    begin_addr1 <= {ADDR_WIDTH{1'b0}};
                end
            end

            state <= S_UPDATE_WAIT;
        end

        // ---------------------------------------------------------------
        // Terminate based on latched "current bank2 window was last"
        // ---------------------------------------------------------------
        S_UPDATE_WAIT: begin
            if (bank2_window_was_last)
                state <= S_WAIT_DONE;
            else
                state <= S_STREAM;
        end

        // ---------------------------------------------------------------
        // Wait for representative odd lane pooling done (bank2 finishes last)
        // ---------------------------------------------------------------
        S_WAIT_DONE: begin
            if (pool_done1_pulse) begin
                state  <= S_DONE;
                done_r <= 1'b1;
            end
        end

        S_DONE: begin
            state <= S_DONE;  // keep existing behavior for now
        end

        default: begin
            state <= S_IDLE;
        end
        endcase
    end
end


integer qi;
always @(*) begin
    Qa_bus = {NUM_LANES*CHANNEL_PAR*DATA_WIDTH{1'b0}};

    for (qi = 0; qi < 6; qi = qi + 1) begin
        // Even lane 2*qi: bank1
        Qa_bus[(2*qi)*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
            { {(CHANNEL_PAR-1)*DATA_WIDTH{1'b0}}, fm_data_in0 };

        // Odd lane 2*qi+1: bank2
        Qa_bus[(2*qi+1)*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
            { {(CHANNEL_PAR-1)*DATA_WIDTH{1'b0}}, fm_data_in1 };
    end
end



wire signed [6*DATA_WIDTH-1:0] exec_wt = weight_rom[exec_tap_cnt];

genvar gf;
generate
for (gf = 0; gf < 6; gf = gf + 1) begin : QW_FILL
    wire signed [DATA_WIDTH-1:0] w_f = exec_wt[gf*DATA_WIDTH +: DATA_WIDTH];

    assign Qw_bus[(2*gf)*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
        { {(CHANNEL_PAR-1)*DATA_WIDTH{1'b0}}, w_f };

    assign Qw_bus[(2*gf+1)*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH] =
        { {(CHANNEL_PAR-1)*DATA_WIDTH{1'b0}}, w_f };
end
assign Qw_bus[12*CHANNEL_PAR*DATA_WIDTH +: 4*CHANNEL_PAR*DATA_WIDTH] =
    {4*CHANNEL_PAR*DATA_WIDTH{1'b0}};
endgenerate


genvar gp;
generate
for (gp = 0; gp < 6; gp = gp + 1) begin : PARAM_FILL
    assign Za_bus  [(2*gp)*DATA_WIDTH +: DATA_WIDTH]   = ZA;
    assign Za_bus  [(2*gp+1)*DATA_WIDTH +: DATA_WIDTH] = ZA;

    assign Zw_bus  [(2*gp)*DATA_WIDTH +: DATA_WIDTH]   = ZW;
    assign Zw_bus  [(2*gp+1)*DATA_WIDTH +: DATA_WIDTH] = ZW;

    assign Zo_bus  [(2*gp)*DATA_WIDTH +: DATA_WIDTH]   = Zo_f[gp];
    assign Zo_bus  [(2*gp+1)*DATA_WIDTH +: DATA_WIDTH] = Zo_f[gp];

    assign M0_bus  [(2*gp)*M0_WIDTH +: M0_WIDTH]       = $signed(M0_f[gp]);
    assign M0_bus  [(2*gp+1)*M0_WIDTH +: M0_WIDTH]     = $signed(M0_f[gp]);

    assign n_bus   [(2*gp)*6 +: 6]                     = n_f[gp];
    assign n_bus   [(2*gp+1)*6 +: 6]                   = n_f[gp];

    assign bias_bus[(2*gp)*32 +: 32]                   = bias_f[gp];
    assign bias_bus[(2*gp+1)*32 +: 32]                 = bias_f[gp];
end

assign Za_bus  [12*DATA_WIDTH +: 4*DATA_WIDTH] = {4*DATA_WIDTH{1'b0}};
assign Zw_bus  [12*DATA_WIDTH +: 4*DATA_WIDTH] = {4*DATA_WIDTH{1'b0}};
assign Zo_bus  [12*DATA_WIDTH +: 4*DATA_WIDTH] = {4*DATA_WIDTH{1'b0}};
assign M0_bus  [12*M0_WIDTH +: 4*M0_WIDTH]     = {4*M0_WIDTH{1'b0}};
assign n_bus   [12*6 +: 4*6]                   = {4*6{1'b0}};
assign bias_bus[12*32 +: 4*32]                 = {4*32{1'b0}};
endgenerate


wire [5:0] even_active = bank1_finished ? 6'b000000 : 6'b111111;
assign lane_active_mask = {4'b0000,
                           1'b1, even_active[5],
                           1'b1, even_active[4],
                           1'b1, even_active[3],
                           1'b1, even_active[2],
                           1'b1, even_active[1],
                           1'b1, even_active[0]};

// Layer 1 always uses pooling
assign pool_bypass = {NUM_LANES{1'b0}};


genvar gd;
generate
for (gd = 0; gd < 6; gd = gd + 1) begin : POOL_DIM
    assign pool_fm_width_bus [(2*gd)*5 +: 5]   = 5'd26;
    assign pool_fm_height_bus[(2*gd)*5 +: 5]   = 5'd12;

    assign pool_fm_width_bus [(2*gd+1)*5 +: 5] = 5'd26;
    assign pool_fm_height_bus[(2*gd+1)*5 +: 5] = 5'd14;
end

assign pool_fm_width_bus [12*5 +: 4*5]   = {4*5{1'b0}};
assign pool_fm_height_bus[12*5 +: 4*5]   = {4*5{1'b0}};
endgenerate


endmodule
