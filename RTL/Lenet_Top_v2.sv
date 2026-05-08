`timescale 1ns / 1ps

// =============================================================================
// Author      : Khanh
// Title       : Lenet_Top_v2
// Description : Top-level controller for the LeNet pipeline using the shared
//               processing engine and ping-pong local memory scheduling.
// =============================================================================
module Lenet_Top_v2 #(
    parameter DATA_WIDTH  = 8,
    parameter ADDR_WIDTH  = 10,
    parameter M0_WIDTH    = 32,
    parameter CHANNEL_PAR = 6,
    parameter NUM_LANES   = 16
)(
    input  wire clk_in,
    input  wire start_in,
    input  wire reset_in,

    input  wire [ADDR_WIDTH-1:0] dma_waddr_in,
    input  wire                  dma_wren_in,
    input  wire [DATA_WIDTH-1:0] dma_wdata_in,

    output wire [3:0] classification_out,
    output wire       done_out
);

// -----------------------------------------------------------------------------
// Reset and start synchronization
// -----------------------------------------------------------------------------
reg reset_ff0_r, reset_ff1_r;
always @(posedge clk_in) begin
    reset_ff0_r <= reset_in;
    reset_ff1_r <= reset_ff0_r;
end
wire reset_w = reset_ff1_r;

reg start_ff0_r, start_ff1_r, start_ff1_d_r;
always @(posedge clk_in) begin
    if (reset_w) begin
        start_ff0_r   <= 1'b0;
        start_ff1_r   <= 1'b0;
        start_ff1_d_r <= 1'b0;
    end else begin
        start_ff0_r   <= start_in;
        start_ff1_r   <= start_ff0_r;
        start_ff1_d_r <= start_ff1_r;
    end
end
wire start_pulse_w = start_ff1_r & ~start_ff1_d_r;

// -----------------------------------------------------------------------------
// Phase controller
// -----------------------------------------------------------------------------
localparam PH_IDLE = 3'd0;
localparam PH_WAKE = 3'd1;
localparam PH_PREP = 3'd2;
localparam PH_L1   = 3'd3;
localparam PH_L2   = 3'd4;
localparam PH_FC   = 3'd5;

reg [2:0] phase_r;
reg l1_run_r, l2_run_r, fc_run_r;
wire core_reset_w = reset_w | (phase_r == PH_WAKE) | (phase_r == PH_PREP);

// -----------------------------------------------------------------------------
// Input image BRAM banks
// -----------------------------------------------------------------------------
wire we_a_w, we_b_w;
wire [ADDR_WIDTH-1:0] waddr_a_w, waddr_b_w;

reg we_a_r, we_b_r;
reg [ADDR_WIDTH-1:0] waddr_a_r, waddr_b_r;
reg [DATA_WIDTH-1:0] dma_wdata_r;

wire [DATA_WIDTH-1:0] bank1_data_w, bank2_data_w;
wire [ADDR_WIDTH-1:0] bank1_rd_addr_w, bank2_rd_addr_w;

input_bank_ctrl #(
    .ADDR_WIDTH   (ADDR_WIDTH),
    .INPUT_WIDTH  (28),
    .INPUT_HEIGHT (28)
) u_bank_ctrl (
    .mnist_wren  (dma_wren_in),
    .mnist_waddr (dma_waddr_in),
    .we_a        (we_a_w),
    .we_b        (we_b_w),
    .waddr_a     (waddr_a_w),
    .waddr_b     (waddr_b_w)
);

always @(posedge clk_in) begin
    if (reset_w) begin
        we_a_r      <= 1'b0;
        we_b_r      <= 1'b0;
        waddr_a_r   <= {ADDR_WIDTH{1'b0}};
        waddr_b_r   <= {ADDR_WIDTH{1'b0}};
        dma_wdata_r <= {DATA_WIDTH{1'b0}};
    end else begin
        we_a_r      <= we_a_w;
        we_b_r      <= we_b_w;
        waddr_a_r   <= waddr_a_w;
        waddr_b_r   <= waddr_b_w;
        dma_wdata_r <= dma_wdata_in;
    end
end

M10K #(
    .ITE_NUM    (28*14),
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH)
) u_input_bank1 (
    .q            (bank1_data_w),
    .d            (dma_wdata_r),
    .write_address(waddr_a_r),
    .read_address (bank1_rd_addr_w),
    .we           (we_a_r),
    .clk          (clk_in)
);

M10K #(
    .ITE_NUM    (28*16),
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH)
) u_input_bank2 (
    .q            (bank2_data_w),
    .d            (dma_wdata_r),
    .write_address(waddr_b_r),
    .read_address (bank2_rd_addr_w),
    .we           (we_b_r),
    .clk          (clk_in)
);

// -----------------------------------------------------------------------------
// Shared engine buses
// -----------------------------------------------------------------------------
wire [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] eng_Qa_bus_w;
wire signed [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] eng_Qw_bus_w;
wire [NUM_LANES*DATA_WIDTH-1:0]                    eng_Za_bus_w;
wire signed [NUM_LANES*DATA_WIDTH-1:0]             eng_Zw_bus_w;
wire [NUM_LANES*DATA_WIDTH-1:0]                    eng_Zo_bus_w;
wire signed [NUM_LANES*M0_WIDTH-1:0]               eng_M0_bus_w;
wire [NUM_LANES*6-1:0]                             eng_n_bus_w;
wire signed [NUM_LANES*32-1:0]                     eng_bias_bus_w;
wire [NUM_LANES-1:0]                               eng_lane_mask_w;
wire [NUM_LANES-1:0]                               eng_pool_bypass_w;
wire [NUM_LANES*5-1:0]                             eng_pool_fw_w, eng_pool_fh_w;
wire                                               eng_En_w, eng_clear_w, eng_last_w;
wire [ADDR_WIDTH-1:0]                              eng_rd_addr_w;
wire                                               eng_rd_en_w;
wire                                               eng_rd_bank_sel_w;
wire                                               eng_wr_bank_sel_w;

wire [NUM_LANES*DATA_WIDTH-1:0] eng_mem_data_w;
wire [NUM_LANES*DATA_WIDTH-1:0] eng_mac_q3_w;
wire [NUM_LANES-1:0]            eng_mac_valid_w;
wire [NUM_LANES-1:0]            eng_pool_done_w;

wire engine_clk_w;
wire engine_clk_ce_w =
       reset_w
    || (phase_r == PH_WAKE)
    || (phase_r == PH_PREP)
    || (phase_r == PH_L1)
    || (phase_r == PH_L2)
    || (phase_r == PH_FC);

fpga_engine_clock_gate u_engine_clk_gate (
    .clk_in  (clk_in),
    .ce      (engine_clk_ce_w),
    .clk_out (engine_clk_w)
);

Shared_Engine #(
    .NUM_LANES       (NUM_LANES),
    .CHANNEL_PAR     (CHANNEL_PAR),
    .DATA_WIDTH      (DATA_WIDTH),
    .ADDR_WIDTH      (ADDR_WIDTH),
    .M0_WIDTH        (M0_WIDTH),
    .LOCAL_MEM_DEPTH (91),
    .MAX_FM_WIDTH    (26),
    .MAX_FM_HEIGHT   (26)
) u_engine (
    .clk                (engine_clk_w),
    .reset              (core_reset_w),
    .Qa_bus             (eng_Qa_bus_w),
    .Qw_bus             (eng_Qw_bus_w),
    .Za_bus             (eng_Za_bus_w),
    .Zw_bus             (eng_Zw_bus_w),
    .Zo_bus             (eng_Zo_bus_w),
    .M0_bus             (eng_M0_bus_w),
    .n_bus              (eng_n_bus_w),
    .bias_bus           (eng_bias_bus_w),
    .lane_active_mask   (eng_lane_mask_w),
    .pool_bypass        (eng_pool_bypass_w),
    .rd_bank_sel        (eng_rd_bank_sel_w),
    .wr_bank_sel        (eng_wr_bank_sel_w),
    .pool_fm_width_bus  (eng_pool_fw_w),
    .pool_fm_height_bus (eng_pool_fh_w),
    .En_in              (eng_En_w),
    .clear_in           (eng_clear_w),
    .last_in            (eng_last_w),
    .rd_addr            (eng_rd_addr_w),
    .rd_en              (eng_rd_en_w),
    .mem_data_out       (eng_mem_data_w),
    .mac_q3_out         (eng_mac_q3_w),
    .mac_q3_valid       (eng_mac_valid_w),
    .pool_done          (eng_pool_done_w)
);

// -----------------------------------------------------------------------------
// L1 controller
// -----------------------------------------------------------------------------
wire [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] l1_Qa_w;
wire signed [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] l1_Qw_w;
wire [NUM_LANES*DATA_WIDTH-1:0]                    l1_Za_w;
wire signed [NUM_LANES*DATA_WIDTH-1:0]             l1_Zw_w;
wire [NUM_LANES*DATA_WIDTH-1:0]                    l1_Zo_w;
wire signed [NUM_LANES*M0_WIDTH-1:0]               l1_M0_w;
wire [NUM_LANES*6-1:0]                             l1_n_w;
wire signed [NUM_LANES*32-1:0]                     l1_bias_w;
wire [NUM_LANES-1:0]                               l1_lane_mask_w, l1_pool_bypass_w;
wire [NUM_LANES*5-1:0]                             l1_pool_fw_w, l1_pool_fh_w;
wire                                               l1_En_w, l1_clear_w, l1_last_w;
wire                                               l1_done_w;

L1_Controller #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .M0_WIDTH   (M0_WIDTH),
    .CHANNEL_PAR(CHANNEL_PAR),
    .NUM_LANES  (NUM_LANES)
) u_l1 (
    .clk                (clk_in),
    .reset              (core_reset_w),
    .run                (l1_run_r),
    .fm_data_in0        (bank1_data_w),
    .fm_data_in1        (bank2_data_w),
    .fm_read_addr0      (bank1_rd_addr_w),
    .fm_read_addr1      (bank2_rd_addr_w),
    .pool_done          (eng_pool_done_w),
    .Qa_bus             (l1_Qa_w),
    .Qw_bus             (l1_Qw_w),
    .Za_bus             (l1_Za_w),
    .Zw_bus             (l1_Zw_w),
    .Zo_bus             (l1_Zo_w),
    .M0_bus             (l1_M0_w),
    .n_bus              (l1_n_w),
    .bias_bus           (l1_bias_w),
    .lane_active_mask   (l1_lane_mask_w),
    .pool_bypass        (l1_pool_bypass_w),
    .pool_fm_width_bus  (l1_pool_fw_w),
    .pool_fm_height_bus (l1_pool_fh_w),
    .En_in              (l1_En_w),
    .clear_in           (l1_clear_w),
    .last_in            (l1_last_w),
    .done               (l1_done_w)
);

// -----------------------------------------------------------------------------
// L2 controller
// -----------------------------------------------------------------------------
wire [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] l2_Qa_w;
wire signed [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] l2_Qw_w;
wire [NUM_LANES*DATA_WIDTH-1:0]                    l2_Za_w;
wire signed [NUM_LANES*DATA_WIDTH-1:0]             l2_Zw_w;
wire [NUM_LANES*DATA_WIDTH-1:0]                    l2_Zo_w;
wire signed [NUM_LANES*M0_WIDTH-1:0]               l2_M0_w;
wire [NUM_LANES*6-1:0]                             l2_n_w;
wire signed [NUM_LANES*32-1:0]                     l2_bias_w;
wire [NUM_LANES-1:0]                               l2_lane_mask_w, l2_pool_bypass_w;
wire [NUM_LANES*5-1:0]                             l2_pool_fw_w, l2_pool_fh_w;
wire                                               l2_En_w, l2_clear_w, l2_last_w;
wire                                               l2_done_w;
wire [ADDR_WIDTH-1:0]                              l2_rd_addr_w;
wire                                               l2_rd_en_w;

L2_Controller #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .M0_WIDTH   (M0_WIDTH),
    .CHANNEL_PAR(CHANNEL_PAR),
    .NUM_LANES  (NUM_LANES)
) u_l2 (
    .clk                (clk_in),
    .reset              (core_reset_w),
    .run                (l2_run_r),
    .l1_mem_data        (eng_mem_data_w),
    .l1_rd_addr         (l2_rd_addr_w),
    .l1_rd_en           (l2_rd_en_w),
    .pool_done          (eng_pool_done_w),
    .Qa_bus             (l2_Qa_w),
    .Qw_bus             (l2_Qw_w),
    .Za_bus             (l2_Za_w),
    .Zw_bus             (l2_Zw_w),
    .Zo_bus             (l2_Zo_w),
    .M0_bus             (l2_M0_w),
    .n_bus              (l2_n_w),
    .bias_bus           (l2_bias_w),
    .lane_active_mask   (l2_lane_mask_w),
    .pool_bypass        (l2_pool_bypass_w),
    .pool_fm_width_bus  (l2_pool_fw_w),
    .pool_fm_height_bus (l2_pool_fh_w),
    .En_in              (l2_En_w),
    .clear_in           (l2_clear_w),
    .last_in            (l2_last_w),
    .done               (l2_done_w)
);

// -----------------------------------------------------------------------------
// FC controller
// -----------------------------------------------------------------------------
wire [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] fc_Qa_w;
wire signed [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] fc_Qw_w;
wire [NUM_LANES*DATA_WIDTH-1:0]                    fc_Za_w;
wire signed [NUM_LANES*DATA_WIDTH-1:0]             fc_Zw_w;
wire [NUM_LANES*DATA_WIDTH-1:0]                    fc_Zo_w;
wire signed [NUM_LANES*M0_WIDTH-1:0]               fc_M0_w;
wire [NUM_LANES*6-1:0]                             fc_n_w;
wire signed [NUM_LANES*32-1:0]                     fc_bias_w;
wire [NUM_LANES-1:0]                               fc_lane_mask_w, fc_pool_bypass_w;
wire [NUM_LANES*5-1:0]                             fc_pool_fw_w, fc_pool_fh_w;
wire                                               fc_En_w, fc_clear_w, fc_last_w;
wire                                               fc_done_w;
wire [ADDR_WIDTH-1:0]                              fc_rd_addr_w;
wire                                               fc_rd_en_w;
wire [DATA_WIDTH-1:0]                              neuron_out_w [0:9];

FC_Controller #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .M0_WIDTH   (M0_WIDTH),
    .CHANNEL_PAR(CHANNEL_PAR),
    .NUM_LANES  (NUM_LANES)
) u_fc (
    .clk                (clk_in),
    .reset              (core_reset_w),
    .run                (fc_run_r),
    .l2_mem_data        (eng_mem_data_w),
    .l2_rd_addr         (fc_rd_addr_w),
    .l2_rd_en           (fc_rd_en_w),
    .mac_q3_out         (eng_mac_q3_w),
    .mac_q3_valid       (eng_mac_valid_w),
    .Qa_bus             (fc_Qa_w),
    .Qw_bus             (fc_Qw_w),
    .Za_bus             (fc_Za_w),
    .Zw_bus             (fc_Zw_w),
    .Zo_bus             (fc_Zo_w),
    .M0_bus             (fc_M0_w),
    .n_bus              (fc_n_w),
    .bias_bus           (fc_bias_w),
    .lane_active_mask   (fc_lane_mask_w),
    .pool_bypass        (fc_pool_bypass_w),
    .pool_fm_width_bus  (fc_pool_fw_w),
    .pool_fm_height_bus (fc_pool_fh_w),
    .En_in              (fc_En_w),
    .clear_in           (fc_clear_w),
    .last_in            (fc_last_w),
    .neuron_out         (neuron_out_w),
    .done               (fc_done_w)
);

// -----------------------------------------------------------------------------
// Softmax / argmax helper
// -----------------------------------------------------------------------------
wire [3:0] softmax_class_w;

sofmax_func #(
    .DATA_WIDTH(DATA_WIDTH)
) u_softmax (
    .clk     (clk_in),
    .run     (phase_r == PH_FC),
    .data_in0(neuron_out_w[0]),
    .data_in1(neuron_out_w[1]),
    .data_in2(neuron_out_w[2]),
    .data_in3(neuron_out_w[3]),
    .data_in4(neuron_out_w[4]),
    .data_in5(neuron_out_w[5]),
    .data_in6(neuron_out_w[6]),
    .data_in7(neuron_out_w[7]),
    .data_in8(neuron_out_w[8]),
    .data_in9(neuron_out_w[9]),
    .hex_out (softmax_class_w)
);

// -----------------------------------------------------------------------------
// Completion pulse and classification latch
// -----------------------------------------------------------------------------
reg fc_done_d_r;
reg done_status_r;
reg [3:0] classification_r;
wire fc_done_seen_pulse_w = fc_done_w & ~fc_done_d_r;

always @(posedge clk_in) begin
    if (reset_w) begin
        fc_done_d_r     <= 1'b0;
        done_status_r   <= 1'b0;
        classification_r <= 4'hF;
    end else begin
        fc_done_d_r <= fc_done_w;

        if (start_pulse_w || (phase_r == PH_WAKE) || (phase_r == PH_PREP)) begin
            done_status_r <= 1'b0;
        end else if (fc_done_seen_pulse_w) begin
            done_status_r <= 1'b1;
        end

        if (phase_r == PH_PREP) begin
            classification_r <= 4'hF;
        end else if (fc_done_seen_pulse_w) begin
            classification_r <= softmax_class_w;
        end
    end
end

assign classification_out = classification_r;
assign done_out = done_status_r;

// -----------------------------------------------------------------------------
// Phase sequencing
// -----------------------------------------------------------------------------
always @(posedge clk_in) begin
    if (reset_w) begin
        phase_r   <= PH_IDLE;
        l1_run_r  <= 1'b0;
        l2_run_r  <= 1'b0;
        fc_run_r  <= 1'b0;
    end else begin
        l1_run_r <= 1'b0;
        l2_run_r <= 1'b0;
        fc_run_r <= 1'b0;

        case (phase_r)
        PH_IDLE: begin
            if (start_pulse_w)
                phase_r <= PH_WAKE;
        end
        PH_WAKE: begin
            phase_r <= PH_PREP;
        end
        PH_PREP: begin
            l1_run_r <= 1'b1;
            phase_r  <= PH_L1;
        end
        PH_L1: begin
            if (l1_done_w) begin
                l2_run_r <= 1'b1;
                phase_r  <= PH_L2;
            end
        end
        PH_L2: begin
            if (l2_done_w) begin
                fc_run_r <= 1'b1;
                phase_r  <= PH_FC;
            end
        end
        PH_FC: begin
            if (fc_done_seen_pulse_w)
                phase_r <= PH_IDLE;
        end
        default: begin
            phase_r <= PH_IDLE;
        end
        endcase
    end
end

// -----------------------------------------------------------------------------
// Bus muxes
// -----------------------------------------------------------------------------
assign eng_Qa_bus_r =
    (phase_r == PH_L1) ? l1_Qa_w :
    (phase_r == PH_L2) ? l2_Qa_w :
    (phase_r == PH_FC) ? fc_Qa_w :
    {NUM_LANES*CHANNEL_PAR*DATA_WIDTH{1'b0}};

assign eng_Qw_bus_r =
    (phase_r == PH_L1) ? l1_Qw_w :
    (phase_r == PH_L2) ? l2_Qw_w :
    (phase_r == PH_FC) ? fc_Qw_w :
    {(NUM_LANES*CHANNEL_PAR*DATA_WIDTH){1'b0}};

assign eng_Za_bus_r =
    (phase_r == PH_L1) ? l1_Za_w :
    (phase_r == PH_L2) ? l2_Za_w :
    (phase_r == PH_FC) ? fc_Za_w :
    {NUM_LANES*DATA_WIDTH{1'b0}};

assign eng_Zw_bus_r =
    (phase_r == PH_L1) ? l1_Zw_w :
    (phase_r == PH_L2) ? l2_Zw_w :
    (phase_r == PH_FC) ? fc_Zw_w :
    {NUM_LANES*DATA_WIDTH{1'b0}};

assign eng_Zo_bus_r =
    (phase_r == PH_L1) ? l1_Zo_w :
    (phase_r == PH_L2) ? l2_Zo_w :
    (phase_r == PH_FC) ? fc_Zo_w :
    {NUM_LANES*DATA_WIDTH{1'b0}};

assign eng_M0_bus_r =
    (phase_r == PH_L1) ? l1_M0_w :
    (phase_r == PH_L2) ? l2_M0_w :
    (phase_r == PH_FC) ? fc_M0_w :
    {NUM_LANES*M0_WIDTH{1'b0}};

assign eng_n_bus_r =
    (phase_r == PH_L1) ? l1_n_w :
    (phase_r == PH_L2) ? l2_n_w :
    (phase_r == PH_FC) ? fc_n_w :
    {NUM_LANES*6{1'b0}};

assign eng_bias_bus_r =
    (phase_r == PH_L1) ? l1_bias_w :
    (phase_r == PH_L2) ? l2_bias_w :
    (phase_r == PH_FC) ? fc_bias_w :
    {NUM_LANES*32{1'b0}};

assign eng_lane_mask_r =
    (phase_r == PH_L1) ? l1_lane_mask_w :
    (phase_r == PH_L2) ? l2_lane_mask_w :
    (phase_r == PH_FC) ? fc_lane_mask_w :
    {NUM_LANES{1'b0}};

assign eng_pool_bypass_r =
    (phase_r == PH_L1) ? l1_pool_bypass_w :
    (phase_r == PH_L2) ? l2_pool_bypass_w :
    (phase_r == PH_FC) ? fc_pool_bypass_w :
    {NUM_LANES{1'b0}};

assign eng_pool_fw_r =
    (phase_r == PH_L1) ? l1_pool_fw_w :
    (phase_r == PH_L2) ? l2_pool_fw_w :
    (phase_r == PH_FC) ? fc_pool_fw_w :
    {NUM_LANES*5{1'b0}};

assign eng_pool_fh_r =
    (phase_r == PH_L1) ? l1_pool_fh_w :
    (phase_r == PH_L2) ? l2_pool_fh_w :
    (phase_r == PH_FC) ? fc_pool_fh_w :
    {NUM_LANES*5{1'b0}};

assign eng_En_r =
    (phase_r == PH_L1) ? l1_En_w :
    (phase_r == PH_L2) ? l2_En_w :
    (phase_r == PH_FC) ? fc_En_w :
    1'b0;

assign eng_clear_r =
    (phase_r == PH_L1) ? l1_clear_w :
    (phase_r == PH_L2) ? l2_clear_w :
    (phase_r == PH_FC) ? fc_clear_w :
    1'b0;

assign eng_last_r =
    (phase_r == PH_L1) ? l1_last_w :
    (phase_r == PH_L2) ? l2_last_w :
    (phase_r == PH_FC) ? fc_last_w :
    1'b0;

assign eng_rd_addr_r =
    (phase_r == PH_L2) ? l2_rd_addr_w :
    (phase_r == PH_FC) ? fc_rd_addr_w :
    {ADDR_WIDTH{1'b0}};

assign eng_rd_en_r =
    (phase_r == PH_L2) ? l2_rd_en_w :
    (phase_r == PH_FC) ? fc_rd_en_w :
    1'b0;

assign eng_wr_bank_sel_w = (phase_r == PH_L2) ? 1'b1 : 1'b0;
assign eng_rd_bank_sel_w = (phase_r == PH_FC) ? 1'b1 : 1'b0;

endmodule
