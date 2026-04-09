module Layer2_Wrapper
#(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10,
    parameter CONV_KERNEL_WIDTH = 3,
    parameter CONV_KERNEL_HEIGHT = 3,
    parameter CONV_FM_WIDTH = 13,
    parameter CONV_FM_HEIGHT = 13,
    parameter CONV_RESULT_WIDTH = 11,
    parameter CONV_RESULT_HEIGHT = 11,
    parameter POOL_KERNEL_WIDTH = 2,
    parameter POOL_KERNEL_HEIGHT = 2,
    parameter LAYER_OUTPUT_WIDTH = 5,
    parameter LAYER_OUTPUT_HEIGHT = 5,
    parameter CHANNEL_NUM = 6,
    parameter M0_WIDTH = 32,
    parameter string WEIGHT_MEMFILE_ALL = "layer2_weights_lutram.mem"
)(
    input logic clk, reset, run,
    input logic  [DATA_WIDTH-1:0] fm_data_in [6],
    input logic [ADDR_WIDTH-1:0] result_read_addr,

    output logic [ADDR_WIDTH-1:0] fm_data_read_addr,
    output logic  [DATA_WIDTH-1:0] result_out[16],
    output logic done
);

localparam int FILTER_NUM      = 16;
localparam int KERNEL_TAP_NUM  = CONV_KERNEL_WIDTH * CONV_KERNEL_HEIGHT; // 9
localparam int WEIGHT_ADDR_W   = (KERNEL_TAP_NUM <= 2) ? 1 : $clog2(KERNEL_TAP_NUM);
localparam int WEIGHT_WORD_W   = DATA_WIDTH * CHANNEL_NUM;               // 48
localparam int ALL_WEIGHT_W    = FILTER_NUM * WEIGHT_WORD_W;             // 768

logic is_last_fm_addr;
logic update_fm_begin_addr;
logic fm_gen_addr_en;
logic  [DATA_WIDTH-1:0] layer_result_op[16];

// Same external organization as your old wrapper
logic signed [WEIGHT_WORD_W-1:0] weight_data_in [16];
logic signed [DATA_WIDTH-1:0]    weight_data_in_F [16][6];
logic [ADDR_WIDTH-1:0]           weight_read_addr;

// Only used in solution 2
logic [ALL_WEIGHT_W-1:0] weight_word_all_q;

generate
    genvar gi;
    for (gi = 0; gi < 16; gi++) begin
        assign result_out[gi] = layer_result_op[gi];
    end
endgenerate

logic [ADDR_WIDTH-1:0] column_count;
logic [ADDR_WIDTH-1:0] row_count;

assign is_last_fm_addr =
    (column_count == CONV_FM_WIDTH  - CONV_KERNEL_WIDTH) &&
    (row_count    == CONV_FM_HEIGHT - CONV_KERNEL_HEIGHT);

always_ff @(posedge clk) begin
    if (reset) begin
        column_count <= '0;
        row_count    <= '0;
    end
    else if (update_fm_begin_addr) begin
        column_count <= (column_count < CONV_FM_WIDTH - CONV_KERNEL_WIDTH) ? column_count + 1'b1 : '0;
        row_count    <= is_last_fm_addr ? '0 :
                        (column_count == CONV_FM_WIDTH - CONV_KERNEL_WIDTH) ? row_count + 1'b1 : row_count;
    end
end

logic [ADDR_WIDTH-1:0] fm_begin_addr;

always_ff @(posedge clk) begin
    if (reset) begin
        fm_begin_addr <= '0;
    end
    else if (update_fm_begin_addr) begin
        fm_begin_addr <= is_last_fm_addr ? '0 :
                         (column_count == CONV_FM_WIDTH - CONV_KERNEL_WIDTH) ? fm_begin_addr + CONV_KERNEL_WIDTH :
                                                                              fm_begin_addr + 1'b1;
    end
end

read_address_gen #(
    .ARRAY_HEIGHT     (CONV_FM_HEIGHT),
    .ARRAY_WIDTH      (CONV_FM_WIDTH),
    .PARTITION_SIZE   (CONV_KERNEL_WIDTH),
    .PARTITION_HEIGHT (CONV_KERNEL_HEIGHT)
) fm_addr_gen (
    .clk       (clk),
    .run       (fm_gen_addr_en),
    .begin_addr(fm_begin_addr),
    .addr_out  (fm_data_read_addr),
    .wr_addr   (),
    .done      ()
);



lutrom_sync #(
    .WIDTH  (ALL_WEIGHT_W),
    .DEPTH  (KERNEL_TAP_NUM),
    .ADDR_W (WEIGHT_ADDR_W),
    .MEMFILE(WEIGHT_MEMFILE_ALL)
) weight_rom_all (
    .clk (clk),
    .en  (1'b1),
    .addr(weight_read_addr[WEIGHT_ADDR_W-1:0]),
    .q   (weight_word_all_q)
);

genvar gf;
generate
    for (gf = 0; gf < FILTER_NUM; gf++) begin : GEN_WIDE_SLICE
        assign weight_data_in[gf] =
            weight_word_all_q[gf*WEIGHT_WORD_W +: WEIGHT_WORD_W];
    end
endgenerate

genvar gfi, gc;
generate
    for (gfi = 0; gfi < FILTER_NUM; gfi++) begin : GEN_FILTER_CH_SPLIT
        for (gc = 0; gc < CHANNEL_NUM; gc++) begin : GEN_CH_SPLIT
            assign weight_data_in_F[gfi][gc] =
                weight_data_in[gfi][gc*DATA_WIDTH +: DATA_WIDTH];
        end
    end
endgenerate
    
// Instances are written explicitly instead of using a generate-for loop,
// because each L2_Fx_process_unit is bound to a unique quantization set.

L2_F0_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F0_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(update_fm_begin_addr),
.fm_gen_addr_en(fm_gen_addr_en),
.result_out(layer_result_op[0]),
.done(done),
.weight_data_in(weight_data_in_F[0]),
.weight_read_addr(weight_read_addr)
);

L2_F1_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F1_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[1]),
.done(),
.weight_data_in(weight_data_in_F[1]),
.weight_read_addr()
);

L2_F2_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F2_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[2]),
.done(),
.weight_data_in(weight_data_in_F[2]),
.weight_read_addr()
);

L2_F3_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F3_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[3]),
.done(),
.weight_data_in(weight_data_in_F[3]),
.weight_read_addr()
);

L2_F4_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F4_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[4]),
.done(),
.weight_data_in(weight_data_in_F[4]),
.weight_read_addr()
);

L2_F5_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F5_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[5]),
.done(),
.weight_data_in(weight_data_in_F[5]),
.weight_read_addr()
);

L2_F6_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F6_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[6]),
.done(),
.weight_data_in(weight_data_in_F[6]),
.weight_read_addr()
);

L2_F7_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F7_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[7]),
.done(),
.weight_data_in(weight_data_in_F[7]),
.weight_read_addr()
);

L2_F8_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F8_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[8]),
.done(),
.weight_data_in(weight_data_in_F[8]),
.weight_read_addr()
);

L2_F9_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F9_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[9]),
.done(),
.weight_data_in(weight_data_in_F[9]),
.weight_read_addr()
);

L2_F10_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F10_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[10]),
.done(),
.weight_data_in(weight_data_in_F[10]),
.weight_read_addr()
);

L2_F11_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F11_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[11]),
.done(),
.weight_data_in(weight_data_in_F[11]),
.weight_read_addr()
);

L2_F12_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F12_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[12]),
.done(),
.weight_data_in(weight_data_in_F[12]),
.weight_read_addr()
);

L2_F13_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F13_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[13]),
.done(),
.weight_data_in(weight_data_in_F[13]),
.weight_read_addr()
);

L2_F14_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F14_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[14]),
.done(),
.weight_data_in(weight_data_in_F[14]),
.weight_read_addr()
);

L2_F15_process_unit #(
.DATA_WIDTH(DATA_WIDTH) ,
.ADDR_WIDTH(ADDR_WIDTH),
.CONV_KERNEL_WIDTH(CONV_KERNEL_WIDTH),
.CONV_KERNEL_HEIGHT(CONV_KERNEL_HEIGHT),
.CONV_FM_WIDTH(CONV_FM_WIDTH),
.CONV_FM_HEIGHT(CONV_FM_HEIGHT),
.CONV_RESULT_WIDTH(CONV_RESULT_WIDTH),
.CONV_RESULT_HEIGHT(CONV_RESULT_HEIGHT),
.POOL_KERNEL_WIDTH(POOL_KERNEL_WIDTH),
.POOL_KERNEL_HEIGHT(POOL_KERNEL_HEIGHT),
.LAYER_OUTPUT_WIDTH(LAYER_OUTPUT_WIDTH),
.LAYER_OUTPUT_HEIGHT(LAYER_OUTPUT_HEIGHT),
.CHANNEL_NUM(CHANNEL_NUM),
.M0_WIDTH(M0_WIDTH)
) F15_process_branch
(
.clk(clk), .reset(reset), .run(run),
.fm_data_in(fm_data_in),
.result_read_addr(result_read_addr),
.is_last_fm_addr(is_last_fm_addr),
.update_fm_begin_addr(),
.fm_gen_addr_en(),
.result_out(layer_result_op[15]),
.done(),
.weight_data_in(weight_data_in_F[15]),
.weight_read_addr()
);

endmodule