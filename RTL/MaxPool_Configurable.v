`timescale 1ns / 1ps
// =============================================================================
// MaxPool_Configurable
// Runtime-configurable 2×2 stride-2 max-pooling unit.
//
// - pool_bypass = 1:
//     pass data through directly (used by FC)
//     detects end-of-stream by falling edge of in_valid
//     emits done pulse and resets internal write address/state
//
// - pool_bypass = 0:
//     normal 2×2 stride-2 max-pooling with Zo floor
// =============================================================================
module MaxPool_Configurable #(
    parameter DATA_WIDTH    = 8,
    parameter ADDR_WIDTH    = 10,
    parameter MAX_FM_WIDTH  = 26,
    parameter MAX_FM_HEIGHT = 26
)(
    input  wire                  clk,
    input  wire                  reset,

    input  wire [4:0]            fm_width,
    input  wire [4:0]            fm_height,

    input  wire                  in_valid,
    input  wire                  pool_bypass,
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire [DATA_WIDTH-1:0] Zo_in,

    output reg  [DATA_WIDTH-1:0] result_out,
    output reg  [ADDR_WIDTH-1:0] w_address_out,
    output reg                   we_out,
    output reg                   done
);

localparam MAX_OUT_WIDTH = MAX_FM_WIDTH / 2;

// -----------------------------------------------------------------------
// Internal state
// -----------------------------------------------------------------------
reg [4:0]            col_q;
reg [4:0]            row_q;
reg [ADDR_WIDTH-1:0] out_addr_q;
reg [DATA_WIDTH-1:0] first_pix_q;

reg [DATA_WIDTH-1:0] top_pair_buf [0:MAX_OUT_WIDTH-1];

reg                  in_valid_d;
reg                  bypass_stream_seen_q;
reg [4:0]            fm_width_cfg_q;
reg [4:0]            fm_height_cfg_q;
reg                  pool_bypass_cfg_q;

integer k;

// -----------------------------------------------------------------------
// Combinational helpers
// -----------------------------------------------------------------------
wire [3:0] pair_idx = col_q >> 1;

wire [DATA_WIDTH-1:0] pair_max;
assign pair_max = (first_pix_q > data_in) ? first_pix_q : data_in;

wire [DATA_WIDTH-1:0] top_val;
assign top_val = top_pair_buf[pair_idx];

wire [DATA_WIDTH-1:0] pair_vs_top;
assign pair_vs_top = (top_val > pair_max) ? top_val : pair_max;

wire [DATA_WIDTH-1:0] pooled_max;
assign pooled_max = (Zo_in > pair_vs_top) ? Zo_in : pair_vs_top;

// last pixel of current FM in pooling mode
wire last_pixel_pool;
assign last_pixel_pool =
    (fm_width  != 5'd0) &&
    (fm_height != 5'd0) &&
    (row_q == (fm_height - 1'b1)) &&
    (col_q == (fm_width  - 1'b1));

// detect end of bypass stream: previous cycle valid, current cycle invalid
wire bypass_stream_end;
assign bypass_stream_end =
    (~in_valid) && in_valid_d && pool_bypass_cfg_q && bypass_stream_seen_q;

// config changed while idle between phases
wire cfg_changed_idle;
assign cfg_changed_idle =
    (~in_valid) &&
    (
        (fm_width_cfg_q      != fm_width)      ||
        (fm_height_cfg_q     != fm_height)     ||
        (pool_bypass_cfg_q   != pool_bypass)
    );

// -----------------------------------------------------------------------
// Main sequential logic
// -----------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        col_q                 <= 5'd0;
        row_q                 <= 5'd0;
        out_addr_q            <= {ADDR_WIDTH{1'b0}};
        first_pix_q           <= {DATA_WIDTH{1'b0}};
        result_out            <= {DATA_WIDTH{1'b0}};
        w_address_out         <= {ADDR_WIDTH{1'b0}};
        we_out                <= 1'b0;
        done                  <= 1'b0;

        in_valid_d            <= 1'b0;
        bypass_stream_seen_q  <= 1'b0;
        fm_width_cfg_q        <= 5'd0;
        fm_height_cfg_q       <= 5'd0;
        pool_bypass_cfg_q     <= 1'b0;

        for (k = 0; k < MAX_OUT_WIDTH; k = k + 1)
            top_pair_buf[k] <= {DATA_WIDTH{1'b0}};
    end
    else begin
        // defaults
        we_out <= 1'b0;
        done   <= 1'b0;

        // ---------------------------------------------------------------
        // 1) End-of-bypass handling
        // When FC stream finishes, emit done and reset internal state so
        // the next phase starts cleanly even without global reset.
        // ---------------------------------------------------------------
        if (bypass_stream_end) begin
            done                 <= 1'b1;
            col_q                <= 5'd0;
            row_q                <= 5'd0;
            out_addr_q           <= {ADDR_WIDTH{1'b0}};
            first_pix_q          <= {DATA_WIDTH{1'b0}};
            bypass_stream_seen_q <= 1'b0;

            for (k = 0; k < MAX_OUT_WIDTH; k = k + 1)
                top_pair_buf[k] <= {DATA_WIDTH{1'b0}};
        end

        // ---------------------------------------------------------------
        // 2) Config change while idle
        // Clear stale state/buffers when switching L1/L2/FC modes.
        // ---------------------------------------------------------------
        if (cfg_changed_idle) begin
            col_q                <= 5'd0;
            row_q                <= 5'd0;
            out_addr_q           <= {ADDR_WIDTH{1'b0}};
            first_pix_q          <= {DATA_WIDTH{1'b0}};
            bypass_stream_seen_q <= 1'b0;

            for (k = 0; k < MAX_OUT_WIDTH; k = k + 1)
                top_pair_buf[k] <= {DATA_WIDTH{1'b0}};
        end

        // ---------------------------------------------------------------
        // 3) Active data processing
        // ---------------------------------------------------------------
        if (in_valid) begin
            if (pool_bypass) begin
                // -------------------------------------------------------
                // Bypass mode (FC)
                // -------------------------------------------------------
                result_out           <= data_in;
                w_address_out        <= out_addr_q;
                we_out               <= 1'b1;
                out_addr_q           <= out_addr_q + 1'b1;
                bypass_stream_seen_q <= 1'b1;
            end
            else begin
                // -------------------------------------------------------
                // Normal 2×2 stride-2 pooling
                // -------------------------------------------------------
                if (col_q[0] == 1'b0) begin
                    // even column: first pixel of horizontal pair
                    first_pix_q <= data_in;
                end
                else begin
                    // odd column: horizontal pair complete
                    if (pair_idx < MAX_OUT_WIDTH) begin
                        if (row_q[0] == 1'b0) begin
                            // even row: store top-row pair max
                            top_pair_buf[pair_idx] <= pair_max;
                        end
                        else begin
                            // odd row: combine with top row => output pooled pixel
                            result_out    <= pooled_max;
                            w_address_out <= out_addr_q;
                            we_out        <= 1'b1;
                            out_addr_q    <= out_addr_q + 1'b1;
                        end
                    end
                end

                // -------------------------------------------------------
                // Advance counters
                // -------------------------------------------------------
                if (last_pixel_pool) begin
                    done       <= 1'b1;
                    col_q      <= 5'd0;
                    row_q      <= 5'd0;
                    out_addr_q <= {ADDR_WIDTH{1'b0}};
                    first_pix_q <= {DATA_WIDTH{1'b0}};

                    for (k = 0; k < MAX_OUT_WIDTH; k = k + 1)
                        top_pair_buf[k] <= {DATA_WIDTH{1'b0}};
                end
                else if (col_q == fm_width - 1'b1) begin
                    col_q <= 5'd0;
                    row_q <= row_q + 1'b1;
                end
                else begin
                    col_q <= col_q + 1'b1;
                end
            end
        end

        // ---------------------------------------------------------------
        // 4) Sample current interface for next-cycle edge/config detect
        // ---------------------------------------------------------------
        in_valid_d          <= in_valid;
        fm_width_cfg_q      <= fm_width;
        fm_height_cfg_q     <= fm_height;
        pool_bypass_cfg_q   <= pool_bypass;
    end
end

endmodule
