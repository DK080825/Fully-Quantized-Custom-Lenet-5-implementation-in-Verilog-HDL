`timescale 1ns / 1ps

module Top_tb;

    // ===============================================================
    // Parameters
    // ===============================================================
    parameter DATA_WIDTH  = 8;
    parameter ADDR_WIDTH  = 10;

    // ===============================================================
    // Clock
    // ===============================================================
    logic clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // ===============================================================
    // DUT I/O
    // ===============================================================
    logic reset_in;
    logic start_in;

    logic [ADDR_WIDTH-1:0] mnist_waddr;
    logic mnist_wren;
    logic signed [DATA_WIDTH-1:0] mnist_wdata;
    logic done;
    logic [3:0] classification;
    logic signed [DATA_WIDTH-1:0] dense_result_out [10];
    
    logic [ADDR_WIDTH-1:0] mem_rd_addr;
    logic [ADDR_WIDTH-1:0] layer1_read_addr;
    logic [ADDR_WIDTH-1:0] layer2_read_addr;
    logic signed [DATA_WIDTH-1:0] mem_output[1];
    logic signed [DATA_WIDTH-1:0] layer1_output [6];
    logic signed [DATA_WIDTH-1:0] layer2_output [16];
    logic l2_run, dense_run;
    logic L1_done, L2_done;
    logic signed [DATA_WIDTH-1:0] l1_output_test[12];
    logic signed [DATA_WIDTH-1:0] dense_result [10];
    logic signed [DATA_WIDTH-1:0] dense_result [10];
    logic signed [DATA_WIDTH-1:0] dense_data_in0[4];
    logic signed [DATA_WIDTH-1:0] dense_data_in1[4];
    logic signed [DATA_WIDTH-1:0] dense_data_in2[4];
    logic signed [DATA_WIDTH-1:0] dense_data_in3[4];
   
    // ===============================================================
    // Instantiate TOP MODULE
    // ===============================================================
    Lenet_Top #(.DATA_WIDTH(DATA_WIDTH))
    dut (
        .clk            (clk),
        .start_in       (start_in),
        .reset_in       (reset_in),
        .mnist_waddr    (mnist_waddr),
        .mnist_wren     (mnist_wren),
        .mnist_wdata    (mnist_wdata),
        .classification (classification),
        .done(done)
        
        /*
        .mem_rd_addr    (mem_rd_addr),
        .layer1_read_addr (layer1_read_addr),
        .layer2_read_addr (layer2_read_addr),
        .mem_output         (mem_output),
        .layer1_output      (layer1_output),
        .layer2_output      (layer2_output),
        .dense_output   (dense_result_out),
        .l2_run_test(l2_run),
        .dense_run_test(dense_run),
       
        .layer1_done(L1_done),
        .layer2_done(L2_done),
        .l1_output_test(l1_output_test),
        .dense_result(dense_result),
        .dense_data_in0(dense_data_in0),
        .dense_data_in1(dense_data_in1),
        .dense_data_in2(dense_data_in2),
        .dense_data_in3(dense_data_in3)
        */
    );

    // ===============================================================
    // MNIST DATA MEMORY (initialized using .mem or .coe)
    // This must have the same port as input_mem
    // ===============================================================
    logic  [ADDR_WIDTH-1:0] mem_raddr;
    logic signed [DATA_WIDTH-1:0] mem_rdata;

    input_image mnist_data_inst (
        .clka  (clk),
        .ena   (1'b1),
        .wea   (1'b0),
        .dina  (27'b0),
        .addra (mem_raddr),
        .douta (mem_rdata)
    );

    // ===============================================================
    // TESTBENCH SEQUENCE
    // ===============================================================
    initial begin
        // Initial values
        reset_in    = 1'b1;
        start_in    = 1'b0;
        mnist_waddr = 0;
        mnist_wren  = 0;
        mnist_wdata = 0;

        $display("\n=== TB START ===");

        // Hold reset
        repeat(20) @(posedge clk);
        reset_in = 1'b0;

        // ===============================================================
        // LOAD MNIST IMAGE INTO TOP INPUT MEMORY
        // ===============================================================
        repeat(3) @(posedge clk);
        $display("Loading MNIST image into input_mem...");
        for (int i = 0; i < 784; i++) begin
            mem_raddr = i;             // read from initialized BRAM
            @(posedge clk);            // wait 1 cycle for mem_rdata
            @(posedge clk);
            @(posedge clk)
            mnist_waddr = i;
            mnist_wdata = mem_rdata;
            mnist_wren = 1'b1;
            @(posedge clk);
            mnist_wren = 1'b0;
        end

        // Stop writing
        mnist_wren = 1'b0;
        $display("MNIST load complete");

        // ===============================================================
        // PULSE START
        // ===============================================================
        @(posedge clk);
        #5;
        start_in = 1'b1;
        @(posedge clk);
        @(posedge clk);
        start_in = 1'b0;

        $display("Start pulse sent.");

        // ===============================================================
        // WAIT FOR FINAL RESULT
        // ===============================================================
        wait (done == 1'b1);   // wait for pipeline finish

        $display("\nCLASSIFICATION RESULT = %0d", classification);
        $display("=== TB END ===\n");

        #50;
        $finish;
    end

endmodule
