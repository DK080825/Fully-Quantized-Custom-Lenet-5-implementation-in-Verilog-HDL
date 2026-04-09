`timescale 1ns/1ps

module INT8_MAC_pipelined #(
    parameter M0_WIDTH = 32,
    parameter CHANNEL_PAR = 6
)(
    input  wire                     CLK,
    input  wire                     RST,

    // activation path: UNSIGNED
    input  wire        [7:0]        Qa_in[CHANNEL_PAR],
    input  wire        [7:0]        Za_in,
    input  wire        [7:0]        Zo_in,

    // weight path: SIGNED
    input  wire signed [7:0]        Qw_in[CHANNEL_PAR],
    input  wire signed [7:0]        Zw_in,

    input  wire                     En_in,

    input  wire signed [M0_WIDTH-1:0] M0_in,
    input  wire        [5:0]        n_in,

    input  wire signed [31:0]       bias_in,
    input  wire                     clear_in,
    input  wire                     last_in,

    // output activation: UNSIGNED
    output reg         [7:0]        Q3_out,
    output reg                      Q3_valid_out
);

localparam integer FRAC_BITS = (M0_WIDTH - 1);
integer i;

// =====================================================
// stage0 registers
// =====================================================
reg v0;

reg        [7:0] s0_Qa [CHANNEL_PAR];
reg signed [7:0] s0_Qw [CHANNEL_PAR];

reg        [7:0] s0_Za;
reg signed [7:0] s0_Zw;

reg signed [M0_WIDTH-1:0] s0_M0;
reg        [5:0]          s0_n;
reg        [7:0]          s0_Zo;
reg signed [31:0]         s0_bias;
reg                       s0_clear, s0_last;

// stage 0: latch input
always @(posedge CLK) begin
    if (RST == 1'b1) begin
        v0 <= 1'b0;
        for (i = 0; i < CHANNEL_PAR; i = i + 1) begin
            s0_Qa[i] <= 8'd0;
            s0_Qw[i] <= 8'sd0;
        end
        s0_Za    <= 8'd0;
        s0_Zw    <= 8'sd0;
        s0_M0    <= '0;
        s0_n     <= 6'd0;
        s0_Zo    <= 8'd0;
        s0_bias  <= 32'sd0;
        s0_clear <= 1'b0;
        s0_last  <= 1'b0;
    end
    else begin
        v0 <= En_in;
        if (En_in) begin
            for (i = 0; i < CHANNEL_PAR; i = i + 1) begin
                s0_Qa[i] <= Qa_in[i];
                s0_Qw[i] <= Qw_in[i];
            end
            s0_Za    <= Za_in;
            s0_Zw    <= Zw_in;
            s0_M0    <= M0_in;
            s0_n     <= n_in;
            s0_Zo    <= Zo_in;
            s0_bias  <= bias_in;
            s0_clear <= clear_in;
            s0_last  <= last_in;
        end
    end
end

// =====================================================
// stage1 registers
// =====================================================
reg v1;
reg signed [8:0] s1_a_off [CHANNEL_PAR];
reg signed [8:0] s1_w_off [CHANNEL_PAR];
reg        [5:0] s1_n;
reg signed [M0_WIDTH-1:0] s1_M0;
reg signed [31:0] s1_bias;
reg        [7:0]  s1_Zo;
reg               s1_clear, s1_last;

// stage 1: subtract zero-point
always @(posedge CLK) begin
    if (RST == 1'b1) begin
        v1 <= 1'b0;
        for (i = 0; i < CHANNEL_PAR; i = i + 1) begin
            s1_a_off[i] <= 9'sd0;
            s1_w_off[i] <= 9'sd0;
        end
        s1_M0    <= '0;
        s1_n     <= 6'd0;
        s1_Zo    <= 8'd0;
        s1_bias  <= 32'sd0;
        s1_clear <= 1'b0;
        s1_last  <= 1'b0;
    end
    else begin
        v1 <= v0;
        if (v0) begin
            for (i = 0; i < CHANNEL_PAR; i = i + 1) begin
                // unsigned activation -> zero-extend first, then signed subtract
                s1_a_off[i] <= $signed({1'b0, s0_Qa[i]}) - $signed({1'b0, s0_Za});
                // signed weight path giữ nguyên
                s1_w_off[i] <= $signed(s0_Qw[i]) - $signed(s0_Zw);
            end
            s1_M0    <= s0_M0;
            s1_n     <= s0_n;
            s1_Zo    <= s0_Zo;
            s1_bias  <= s0_bias;
            s1_clear <= s0_clear;
            s1_last  <= s0_last;
        end
    end
end

// =====================================================
// stage2 registers
// =====================================================
reg v2;
reg signed [17:0] s2_prod [CHANNEL_PAR];
reg        [5:0]  s2_n;
reg signed [M0_WIDTH-1:0] s2_M0;
reg signed [31:0] s2_bias;
reg        [7:0]  s2_Zo;
reg               s2_clear, s2_last;

// stage 2: multiply
always @(posedge CLK) begin
    if (RST == 1'b1) begin
        v2 <= 1'b0;
        for (i = 0; i < CHANNEL_PAR; i = i + 1) begin
            s2_prod[i] <= 18'sd0;
        end
        s2_M0    <= '0;
        s2_n     <= 6'd0;
        s2_Zo    <= 8'd0;
        s2_bias  <= 32'sd0;
        s2_clear <= 1'b0;
        s2_last  <= 1'b0;
    end
    else begin
        v2 <= v1;
        if (v1) begin
            for (i = 0; i < CHANNEL_PAR; i = i + 1) begin
                s2_prod[i] <= s1_a_off[i] * s1_w_off[i];
            end
            s2_M0    <= s1_M0;
            s2_n     <= s1_n;
            s2_Zo    <= s1_Zo;
            s2_bias  <= s1_bias;
            s2_clear <= s1_clear;
            s2_last  <= s1_last;
        end
    end
end

localparam int PROD_W = 18;
localparam int SUM_W  = PROD_W + $clog2(CHANNEL_PAR);

wire signed [SUM_W-1:0] s2_prod_sum_w;

adder_tree_signed #(
    .N    (CHANNEL_PAR),
    .IN_W (PROD_W),
    .OUT_W(SUM_W)
) u_s2_adder_tree (
    .din (s2_prod),
    .dout(s2_prod_sum_w)
);

// =====================================================
// stage3 registers
// =====================================================
reg v3;
reg signed [31:0] s3_acc;
reg        [5:0]  s3_n;
reg signed [M0_WIDTH-1:0] s3_M0;
reg signed [31:0] s3_bias;
reg        [7:0]  s3_Zo;
reg               s3_last;

// stage 3: accumulate
always @(posedge CLK) begin
    if (RST == 1'b1) begin
        v3 <= 1'b0;
        s3_acc  <= 32'sd0;
        s3_M0   <= '0;
        s3_n    <= 6'd0;
        s3_Zo   <= 8'd0;
        s3_bias <= 32'sd0;
        s3_last <= 1'b0;
    end
    else begin
        v3 <= v2;
        if (v2) begin
        if (s2_clear)
            s3_acc <= $signed({{(32-SUM_W){s2_prod_sum_w[SUM_W-1]}}, s2_prod_sum_w});
        else
            s3_acc <= s3_acc + $signed({{(32-SUM_W){s2_prod_sum_w[SUM_W-1]}}, s2_prod_sum_w});

            s3_M0   <= s2_M0;
            s3_n    <= s2_n;
            s3_Zo   <= s2_Zo;
            s3_bias <= s2_bias;
            s3_last <= s2_last;
        end
        else begin
            s3_last <= 1'b0;
        end
    end
end

// =====================================================
// stage4 registers
// =====================================================
reg v4;
reg signed [63:0] s4_mul_M;
reg        [5:0]  s4_n;
reg        [7:0]  s4_Zo;

// stage 4: add bias and requant multiply
always @(posedge CLK) begin
    if (RST == 1'b1) begin
        v4       <= 1'b0;
        s4_mul_M <= 64'sd0;
        s4_n     <= 6'd0;
        s4_Zo    <= 8'd0;
    end
    else begin
        v4 <= (v3 & s3_last);
        if (v3 && s3_last) begin
            s4_mul_M <= $signed(s3_M0) * $signed(s3_acc + s3_bias);
            s4_n     <= s3_n;
            s4_Zo    <= s3_Zo;
        end
    end
end

// =====================================================
// stage5 registers
// =====================================================
reg v5;
reg signed [31:0] s5_roundedProd;
reg        [7:0]  s5_Zo;

wire [7:0] sh_full = FRAC_BITS + s4_n;
wire [5:0] shift_amt = (sh_full > 8'd63) ? 6'd63 : sh_full;

wire signed [63:0] round_add =
    (shift_amt == 0) ? 64'sd0 :
    (s4_mul_M >= 0 ?  (64'sd1 <<< (shift_amt-1))
                   : ((64'sd1 <<< (shift_amt-1)) - 1));

wire signed [63:0] scaledF =
    (shift_amt == 0) ? s4_mul_M
                     : ((s4_mul_M + round_add) >>> shift_amt);

// stage 5: rounding + shift right
always @(posedge CLK) begin
    if (RST == 1'b1) begin
        v5 <= 1'b0;
        s5_roundedProd <= 32'sd0;
        s5_Zo <= 8'd0;
    end
    else begin
        v5 <= v4;
        if (v4) begin
            s5_roundedProd <= $signed(scaledF[31:0]);
            s5_Zo <= s4_Zo;
        end
    end
end

// =====================================================
// stage6: add Zo and saturate to UINT8
// =====================================================
wire signed [31:0] zo_ext = $signed({24'd0, s5_Zo});
wire signed [32:0] raw_result = $signed(s5_roundedProd) + zo_ext;

always @(posedge CLK) begin
    if (RST == 1'b1) begin
        Q3_out <= 8'd0;
        Q3_valid_out <= 1'b0;
    end
    else begin
        if (v5) begin
            Q3_valid_out <= 1'b1;
            if (raw_result > 33'sd255)
                Q3_out <= 8'd255;
            else if (raw_result < 33'sd0)
                Q3_out <= 8'd0;
            else
                Q3_out <= raw_result[7:0];
        end
        else begin
            Q3_valid_out <= 1'b0;
            Q3_out <= 8'd0;
        end
    end
end

endmodule