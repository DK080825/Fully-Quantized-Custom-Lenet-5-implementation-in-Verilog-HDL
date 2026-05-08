`timescale 1ns / 1ps

module tb_Lenet_Top_v2_pingpong;

// ============================================================
// Parameters
// ============================================================
localparam DATA_WIDTH  = 8;
localparam ADDR_WIDTH  = 10;
localparam M0_WIDTH    = 32;
localparam CHANNEL_PAR = 6;
localparam NUM_LANES   = 16;

localparam CLK_PERIOD  = 10;
localparam IMG_W       = 28;
localparam IMG_H       = 28;
localparam IMG_PIXELS  = IMG_W * IMG_H;

localparam NUM_TESTS   = 3;

// Timeout đủ lớn cho L1 + L2 + FC
localparam TIMEOUT_CYCLES = 200000;

// ============================================================
// DUT signals
// ============================================================
reg clk;
reg reset_in;
reg start_in;

reg  [ADDR_WIDTH-1:0] mnist_waddr;
reg                   mnist_wren;
reg  [DATA_WIDTH-1:0] mnist_wdata;

wire [3:0] classification;
wire       done;

// ============================================================
// Image storage in TB
// ============================================================
reg [DATA_WIDTH-1:0] img_mem [0:IMG_PIXELS-1];

// File names
string img_file [0:NUM_TESTS-1];

// Expected labels
// Sửa lại theo đúng label thật của 3 ảnh bạn dùng.
integer expected_label [0:NUM_TESTS-1];

// Result counters
integer pass_count;
integer fail_count;

// ============================================================
// DUT
// ============================================================
Lenet_Top_v2 #(
    .DATA_WIDTH  (DATA_WIDTH),
    .ADDR_WIDTH  (ADDR_WIDTH),
    .M0_WIDTH    (M0_WIDTH),
    .CHANNEL_PAR (CHANNEL_PAR),
    .NUM_LANES   (NUM_LANES)
) dut (
    .clk            (clk),
    .start_in       (start_in),
    .reset_in       (reset_in),

    .dma_waddr      (mnist_waddr),
    .dma_wren       (mnist_wren),
    .dma_wdata      (mnist_wdata),

    .classification (classification),
    .done           (done)
);

// ============================================================
// Clock
// ============================================================
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// ============================================================
// Task: global reset
// ============================================================
task apply_reset;
begin
    reset_in    = 1'b1;
    start_in    = 1'b0;
    mnist_wren  = 1'b0;
    mnist_waddr = {ADDR_WIDTH{1'b0}};
    mnist_wdata = {DATA_WIDTH{1'b0}};

    repeat (10) @(posedge clk);

    reset_in = 1'b0;

    repeat (10) @(posedge clk);
end
endtask

// ============================================================
// Task: clear TB image buffer
// ============================================================
task clear_img_mem;
    integer i;
begin
    for (i = 0; i < IMG_PIXELS; i = i + 1) begin
        img_mem[i] = {DATA_WIDTH{1'b0}};
    end
end
endtask

// ============================================================
// Task: load one image file into DUT through mnist write port
// ============================================================
task load_image_to_dut;
    input string file_name;
    integer i;
begin
    $display("");
    $display("============================================================");
    $display("[TB] LOAD IMAGE: %s", file_name);
    $display("============================================================");

    clear_img_mem();

    // File .mem cần có 784 dòng, mỗi dòng là 1 byte hex, ví dụ:
    // 00
    // 1A
    // FF
    $readmemh(file_name, img_mem);

    // Ghi lần lượt 784 pixel vào input banks qua DMA loader interface
    mnist_wren = 1'b0;
    @(posedge clk);

    for (i = 0; i < IMG_PIXELS; i = i + 1) begin
        @(negedge clk);
        mnist_wren  = 1'b1;
        mnist_waddr = i[ADDR_WIDTH-1:0];
        mnist_wdata = img_mem[i];

        @(posedge clk);
    end

    @(negedge clk);
    mnist_wren  = 1'b0;
    mnist_waddr = {ADDR_WIDTH{1'b0}};
    mnist_wdata = {DATA_WIDTH{1'b0}};

    repeat (5) @(posedge clk);

    $display("[TB] Image loaded done: %s", file_name);
end
endtask

// ============================================================
// Task: pulse start and wait done
// ============================================================
task run_inference;
    input integer test_id;
    input integer exp_label;

    integer cycle_count;
    reg [3:0] got_class;
    reg       done_seen;
begin
    $display("");
    $display("============================================================");
    $display("[TB] START INFERENCE %0d", test_id);
    $display("============================================================");

    // Đưa start_in lên theo cạnh xuống để top bắt được qua synchronizer.
    @(negedge clk);
    start_in = 1'b1;

    repeat (3) @(posedge clk);

    @(negedge clk);
    start_in = 1'b0;

    // Wait done: đợi tới khi thấy cạnh lên của done, tránh bắt nhầm mức cũ.
    cycle_count = 0;
    done_seen   = 1'b0;

    while ((done_seen == 1'b0) && (cycle_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
        if (done === 1'b1) begin
            done_seen = 1'b1;
        end
    end

    if (done_seen == 1'b0) begin
        $display("[TB][FAIL] Test %0d timeout after %0d cycles",
                 test_id, TIMEOUT_CYCLES);
        fail_count = fail_count + 1;
    end
    else begin
        // Chờ thêm 1 chu kỳ để classification_reg ổn định sau done.
        @(posedge clk);
        got_class = classification;

        $display("[TB] Test %0d done after %0d cycles", test_id, cycle_count);
        $display("[TB] Expected class = %0d", exp_label);
        $display("[TB] Got class      = %0d", got_class);

        if (got_class == exp_label) begin
            $display("[TB][PASS] Test %0d classification matched", test_id);
            pass_count = pass_count + 1;
        end
        else begin
            $display("[TB][FAIL] Test %0d classification mismatch", test_id);
            fail_count = fail_count + 1;
        end
    end

    // Chờ top quay về PH_IDLE trước khi nạp ảnh kế tiếp.
    repeat (20) @(posedge clk);
end
endtask

// ============================================================
// Main test
// ============================================================
integer t;

initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_Lenet_Top_v2_pingpong);
end
initial begin
    // --------------------------------------------------------
    // Sửa 3 file ảnh và expected label tại đây
    // --------------------------------------------------------
    img_file[0] = "digit_7.mem";
    img_file[1] = "digit_8.mem";
    img_file[2] = "digit_9.mem";

    expected_label[0] = 7;
    expected_label[1] = 8;
    expected_label[2] = 9;

    pass_count = 0;
    fail_count = 0;

    $display("");
    $display("============================================================");
    $display("TB: Lenet_Top_v2 ping-pong multi-image test");
    $display("Number of images: %0d", NUM_TESTS);
    $display("============================================================");

    apply_reset();

    // --------------------------------------------------------
    // Chạy 3 ảnh liên tiếp.
    // Reset toàn hệ thống 1 lần ở đầu.
    // Sau mỗi ảnh, top tự soft-reset engine/controller bằng PH_PREP.
    // --------------------------------------------------------
    for (t = 0; t < NUM_TESTS; t = t + 1) begin
        load_image_to_dut(img_file[t]);
        run_inference(t, expected_label[t]);
    end

    $display("");
    $display("============================================================");
    $display("SUMMARY");
    $display("============================================================");
    $display("PASS = %0d", pass_count);
    $display("FAIL = %0d", fail_count);

    if (fail_count == 0) begin
        $display("[TB] ALL TESTS PASSED");
    end
    else begin
        $display("[TB] SOME TESTS FAILED");
    end

    $display("============================================================");

    repeat (20) @(posedge clk);
    $finish;
end

endmodule