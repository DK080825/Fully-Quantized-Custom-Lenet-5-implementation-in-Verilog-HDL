`timescale 1ns / 1ps
// =============================================================================
// Author      : Khanh
// Title       : Shared_Engine
// Description : Shared compute fabric for the LeNet pipeline. It contains the
//               MAC lanes, configurable pooling, and local output memories used
//               by all network stages.
// =============================================================================
module Shared_Engine #(
    parameter NUM_LANES       = 16,
    parameter CHANNEL_PAR     = 6,
    parameter DATA_WIDTH      = 8,
    parameter ADDR_WIDTH      = 10,
    parameter M0_WIDTH        = 32,
    parameter LOCAL_MEM_DEPTH = 91,   // max pooled pixels per output channel
    parameter MAX_FM_WIDTH    = 26,
    parameter MAX_FM_HEIGHT   = 26
)(
    input  wire clk,
    input  wire reset,

    // ================================================================
    // Per-lane activation bus  (channel_valid_mask applied by controller)
    // Lane i occupies bits [i*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH]
    // ================================================================
    input  wire [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] Qa_bus,   // unsigned
    input  wire signed [NUM_LANES*CHANNEL_PAR*DATA_WIDTH-1:0] Qw_bus,  // signed

    // Per-lane zero-points
    input  wire [NUM_LANES*DATA_WIDTH-1:0]   Za_bus,
    input  wire signed [NUM_LANES*DATA_WIDTH-1:0] Zw_bus,
    input  wire [NUM_LANES*DATA_WIDTH-1:0]   Zo_bus,

    // Per-lane requantization parameters
    input  wire signed [NUM_LANES*M0_WIDTH-1:0] M0_bus,
    input  wire        [NUM_LANES*6-1:0]         n_bus,
    input  wire signed [NUM_LANES*32-1:0]        bias_bus,

    // ================================================================
    // Control signals (shared, from active controller)
    // ================================================================
    input  wire [NUM_LANES-1:0] lane_active_mask,   // 0 = disable this lane activity
    input  wire [NUM_LANES-1:0] pool_bypass,         // 1 = bypass pool unit

    // Ping-pong local memory bank select
    //   wr_bank_sel = bank used by the current layer to store its output
    //   rd_bank_sel = bank used by the next layer to read previous results
    // Intended schedule:
    //   L1: write bank 0
    //   L2: read bank 0, write bank 1
    //   FC: read bank 1
    input  wire rd_bank_sel,
    input  wire wr_bank_sel,

    // Per-lane pool FM dimensions (runtime)
    input  wire [NUM_LANES*5-1:0] pool_fm_width_bus,
    input  wire [NUM_LANES*5-1:0] pool_fm_height_bus,

    input  wire En_in,      // global MAC enable (gated per-lane by active_mask)
    input  wire clear_in,   // clear accumulator (tap 0)
    input  wire last_in,    // last tap of kernel window

    // ================================================================
    // Local memory read interface (next controller reads previous results)
    // ================================================================
    input  wire [ADDR_WIDTH-1:0]              rd_addr,
    input  wire                               rd_en,
    output wire [NUM_LANES*DATA_WIDTH-1:0]    mem_data_out,

    // ================================================================
    // Direct MAC Q3 output (FC layer feeds softmax without going through mem)
    // ================================================================
    output wire [NUM_LANES*DATA_WIDTH-1:0] mac_q3_out,
    output wire [NUM_LANES-1:0]            mac_q3_valid,

    // Pool done per lane (controller uses this to detect layer completion)
    output wire [NUM_LANES-1:0] pool_done
);

// -----------------------------------------------------------------------
// Local mem depth clog2
// -----------------------------------------------------------------------
/*function integer clog2;
    input integer value;
    integer j;
    begin
        value = value - 1;
        for (j = 0; value > 0; j = j + 1) value = value >> 1;
        clog2 = (j == 0) ? 1 : j;
    end
endfunction*/

localparam MEM_AW = $clog2(LOCAL_MEM_DEPTH);   // address width for local mem

// -----------------------------------------------------------------------
// Generate: 16 lanes
// -----------------------------------------------------------------------
genvar gi;
generate
for (gi = 0; gi < NUM_LANES; gi = gi + 1) begin : LANE

    // ------------------------------------------------------------------
    // Slice per-lane signals from buses
    // ------------------------------------------------------------------
    wire [CHANNEL_PAR*DATA_WIDTH-1:0] Qa_lane = Qa_bus[gi*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH];
    wire signed [CHANNEL_PAR*DATA_WIDTH-1:0] Qw_lane = Qw_bus[gi*CHANNEL_PAR*DATA_WIDTH +: CHANNEL_PAR*DATA_WIDTH];
    wire [DATA_WIDTH-1:0] Za_lane   = Za_bus  [gi*DATA_WIDTH +: DATA_WIDTH];
    wire signed [DATA_WIDTH-1:0] Zw_lane = Zw_bus[gi*DATA_WIDTH +: DATA_WIDTH];
    wire [DATA_WIDTH-1:0] Zo_lane   = Zo_bus  [gi*DATA_WIDTH +: DATA_WIDTH];
    wire signed [M0_WIDTH-1:0] M0_lane = M0_bus[gi*M0_WIDTH +: M0_WIDTH];
    wire [5:0] n_lane               = n_bus   [gi*6 +: 6];
    wire signed [31:0] bias_lane    = bias_bus[gi*32 +: 32];
    wire [4:0] fmw_lane             = pool_fm_width_bus [gi*5 +: 5];
    wire [4:0] fmh_lane             = pool_fm_height_bus[gi*5 +: 5];

    // Lane activity gating:
    // lane_active_mask masks En_in per lane.
    // This is NOT true clock gating.
    // True coarse-grain clock gating is implemented outside this module
    // at top-level by gating the whole Shared_Engine clock.
    wire lane_en = En_in & lane_active_mask[gi];

    // ------------------------------------------------------------------
    // INT8_MAC_pipelined
    // ------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] mac_q3;
    wire                  mac_valid;

    INT8_MAC_pipelined #(
        .M0_WIDTH   (M0_WIDTH),
        .CHANNEL_PAR(CHANNEL_PAR)
    ) u_mac (
        .CLK         (clk),
        .RST         (reset),
        .Qa_in       (Qa_lane),
        .Qw_in       (Qw_lane),
        .Za_in       (Za_lane),
        .Zw_in       (Zw_lane),
        .Zo_in       (Zo_lane),
        .En_in       (lane_en),
        .M0_in       (M0_lane),
        .n_in        (n_lane),
        .bias_in     (bias_lane),
        .clear_in    (clear_in),
        .last_in     (last_in),
        .Q3_out      (mac_q3),
        .Q3_valid_out(mac_valid)
    );

    assign mac_q3_out  [gi*DATA_WIDTH +: DATA_WIDTH] = mac_q3;
    assign mac_q3_valid[gi]                           = mac_valid;

    // ------------------------------------------------------------------
    // MaxPool_Configurable
    // ------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] pool_result;
    wire [ADDR_WIDTH-1:0] pool_waddr;
    wire                  pool_we;
    wire                  pool_done_raw;

    MaxPool_Configurable #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .MAX_FM_WIDTH (MAX_FM_WIDTH),
        .MAX_FM_HEIGHT(MAX_FM_HEIGHT)
    ) u_pool (
        .clk          (clk),
        .reset        (reset),
        .fm_width     (fmw_lane),
        .fm_height    (fmh_lane),
        .in_valid     (mac_valid),
        .pool_bypass  (pool_bypass[gi]),
        .data_in      (mac_q3),
        .Zo_in        (Zo_lane),
        .result_out   (pool_result),
        .w_address_out(pool_waddr),
        .we_out       (pool_we),
        .done         (pool_done_raw)
    );

    // ------------------------------------------------------------------
    // Local output memory
    // - true low-power intent here is EN-controlled read/write
    // - inferred simple dual-port RAM style
    // ------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] pool_result_q;
    reg [ADDR_WIDTH-1:0] pool_waddr_q;
    reg                  pool_we_q;
    reg                  pool_done_q;


    (* ram_style = "block", ramstyle = "no_rw_check, M10K" *)
    reg [DATA_WIDTH-1:0] local_mem0 [0:LOCAL_MEM_DEPTH-1];

    (* ram_style = "block", ramstyle = "no_rw_check, M10K" *)
    reg [DATA_WIDTH-1:0] local_mem1 [0:LOCAL_MEM_DEPTH-1];

    reg [DATA_WIDTH-1:0] mem_rd_data;
    integer mi;

    initial begin
        for (mi = 0; mi < LOCAL_MEM_DEPTH; mi = mi + 1) begin
            local_mem0[mi] = {DATA_WIDTH{1'b0}};
            local_mem1[mi] = {DATA_WIDTH{1'b0}};
        end
        mem_rd_data = {DATA_WIDTH{1'b0}};
    end

    // Write enable only when active lane really produces a pooled result.
    // IMPORTANT:
    //   The previous version had one local_mem per lane. During L2, the
    //   engine read L1 output and overwrote L2 output in the same memory.
    //   Ping-pong memory fixes that:
    //      wr_bank_sel = 0: commit pooled output to local_mem0
    //      wr_bank_sel = 1: commit pooled output to local_mem1
    always @(posedge clk) begin
        if (reset) begin
            pool_result_q <= {DATA_WIDTH{1'b0}};
            pool_waddr_q  <= {ADDR_WIDTH{1'b0}};
            pool_we_q     <= 1'b0;
            pool_done_q   <= 1'b0;
        end
        else begin
            // stage register from pool output
            pool_result_q <= pool_result;
            pool_waddr_q  <= pool_waddr;
            pool_we_q     <= pool_we & ~pool_bypass[gi];

            // delay done 1 cycle so controller sees completion
            // only after final pooled value has had a chance to commit
            pool_done_q   <= pool_done_raw;

            // commit previous cycle pooled output to selected write bank
            if (pool_we_q) begin
                if (wr_bank_sel)
                    local_mem1[pool_waddr_q[MEM_AW-1:0]] <= pool_result_q;
                else
                    local_mem0[pool_waddr_q[MEM_AW-1:0]] <= pool_result_q;
            end
        end

        // Debug
        if (!reset && (gi == 0 || gi == 2 || gi == 10)) begin
            if (pool_we || pool_we_q || pool_done_raw || pool_done_q) begin
                $display("%t [ENG-L%0d] wr_bank=%0d rd_bank=%0d pool_we=%0b pool_we_q=%0b waddr=%0d waddr_q=%0d data=%0d data_q=%0d lane_active=%0b pool_done_raw=%0b pool_done_q=%0b",
                         $time, gi,
                         wr_bank_sel, rd_bank_sel,
                         pool_we, pool_we_q,
                         pool_waddr, pool_waddr_q,
                         pool_result, pool_result_q,
                         lane_active_mask[gi],
                         pool_done_raw, pool_done_q);
            end
        end
    end

    assign pool_done[gi] = pool_done_q;

    // Read only when rd_en is asserted.
    //      rd_bank_sel = 0: read from local_mem0
    //      rd_bank_sel = 1: read from local_mem1
    always @(posedge clk) begin
        if (reset) begin
            mem_rd_data <= {DATA_WIDTH{1'b0}};
        end
        else if (rd_en) begin
            if (rd_bank_sel)
                mem_rd_data <= local_mem1[rd_addr[MEM_AW-1:0]];
            else
                mem_rd_data <= local_mem0[rd_addr[MEM_AW-1:0]];
        end
    end

    assign mem_data_out[gi*DATA_WIDTH +: DATA_WIDTH] = mem_rd_data;

    // Debug only
    reg [15:0] dbg_mac_idx;
    wire [4:0] dbg_mac_x = dbg_mac_idx % fmw_lane;
    wire [4:0] dbg_mac_y = dbg_mac_idx / fmw_lane;

    always @(posedge clk) begin
        if (reset) begin
            dbg_mac_idx <= 16'd0;
        end
        else if (gi == 10 && mac_valid) begin
            $display("%t [MAC-L10] idx=%0d y=%0d x=%0d q3=%0d",
                    $time, dbg_mac_idx, dbg_mac_y, dbg_mac_x, mac_q3);

            dbg_mac_idx <= dbg_mac_idx + 1'b1;
        end
    end

    // ===============================================================
    // DEBUG: MAC output before pooling for lane 10
    // L1 bank0/even conv output shape: 12 x 26
    // Target pool addr 8 -> conv windows:
    //   (0,16), (0,17), (1,16), (1,17)
    // ===============================================================
    reg [15:0] dbg_l10_mac_idx;

    wire [4:0] dbg_l10_mac_y;
    wire [4:0] dbg_l10_mac_x;

    assign dbg_l10_mac_y = dbg_l10_mac_idx / 26;
    assign dbg_l10_mac_x = dbg_l10_mac_idx % 26;

    always @(posedge clk) begin
        if (reset) begin
            dbg_l10_mac_idx <= 16'd0;
        end
        else if (gi == 10 && mac_valid) begin
            if (
                ((dbg_l10_mac_y == 5'd0) && 
                    ((dbg_l10_mac_x == 5'd16) || (dbg_l10_mac_x == 5'd17))) ||
                ((dbg_l10_mac_y == 5'd1) && 
                    ((dbg_l10_mac_x == 5'd16) || (dbg_l10_mac_x == 5'd17)))
            ) begin
                $display("%t [MAC-L10-A8] mac_y=%0d mac_x=%0d q3=%0d",
                        $time,
                        dbg_l10_mac_y,
                        dbg_l10_mac_x,
                        mac_q3);
            end

            dbg_l10_mac_idx <= dbg_l10_mac_idx + 1'b1;
        end
    end

end // for LANE
endgenerate

endmodule
