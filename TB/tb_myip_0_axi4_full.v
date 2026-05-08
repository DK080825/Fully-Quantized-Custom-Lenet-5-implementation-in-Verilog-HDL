`timescale 1ns/1ps

module tb_myip_0_axi4_full;
    localparam integer ADDR_WIDTH = 10;
    localparam integer IMG_SIZE    = 784;
    localparam [ADDR_WIDTH-1:0] START_BASE  = 10'h000;
    localparam [ADDR_WIDTH-1:0] RESET_BASE  = 10'h004;
    localparam [ADDR_WIDTH-1:0] RESULT_BASE = 10'h010;
    localparam [ADDR_WIDTH-1:0] DONE_BASE   = 10'h014;
    localparam [ADDR_WIDTH-1:0] DMA_BASE    = 10'h020;

    reg s00_axi_aclk;
    reg s00_axi_aresetn;

    reg  [0:0] s00_axi_awid;
    reg  [9:0] s00_axi_awaddr;
    reg  [7:0] s00_axi_awlen;
    reg  [2:0] s00_axi_awsize;
    reg  [1:0] s00_axi_awburst;
    reg        s00_axi_awlock;
    reg  [3:0] s00_axi_awcache;
    reg  [2:0] s00_axi_awprot;
    reg  [3:0] s00_axi_awqos;
    reg  [3:0] s00_axi_awregion;
    reg  [0:0] s00_axi_awuser;
    reg        s00_axi_awvalid;
    wire       s00_axi_awready;

    reg  [31:0] s00_axi_wdata;
    reg  [3:0]  s00_axi_wstrb;
    reg         s00_axi_wlast;
    reg  [0:0]  s00_axi_wuser;
    reg         s00_axi_wvalid;
    wire        s00_axi_wready;

    wire [0:0] s00_axi_bid;
    wire [1:0] s00_axi_bresp;
    wire [0:0] s00_axi_buser;
    wire       s00_axi_bvalid;
    reg        s00_axi_bready;

    reg  [0:0] s00_axi_arid;
    reg  [9:0] s00_axi_araddr;
    reg  [7:0] s00_axi_arlen;
    reg  [2:0] s00_axi_arsize;
    reg  [1:0] s00_axi_arburst;
    reg        s00_axi_arlock;
    reg  [3:0] s00_axi_arcache;
    reg  [2:0] s00_axi_arprot;
    reg  [3:0] s00_axi_arqos;
    reg  [3:0] s00_axi_arregion;
    reg  [0:0] s00_axi_aruser;
    reg        s00_axi_arvalid;
    wire       s00_axi_arready;

    wire [0:0] s00_axi_rid;
    wire [31:0] s00_axi_rdata;
    wire [1:0] s00_axi_rresp;
    wire       s00_axi_rlast;
    wire [0:0] s00_axi_ruser;
    wire       s00_axi_rvalid;
    reg        s00_axi_rready;

    reg [7:0] test_image [0:IMG_SIZE-1];

    integer i;

    myip_0 dut (
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .s00_axi_awid(s00_axi_awid),
        .s00_axi_awaddr(s00_axi_awaddr),
        .s00_axi_awlen(s00_axi_awlen),
        .s00_axi_awsize(s00_axi_awsize),
        .s00_axi_awburst(s00_axi_awburst),
        .s00_axi_awlock(s00_axi_awlock),
        .s00_axi_awcache(s00_axi_awcache),
        .s00_axi_awprot(s00_axi_awprot),
        .s00_axi_awqos(s00_axi_awqos),
        .s00_axi_awregion(s00_axi_awregion),
        .s00_axi_awuser(s00_axi_awuser),
        .s00_axi_awvalid(s00_axi_awvalid),
        .s00_axi_awready(s00_axi_awready),
        .s00_axi_wdata(s00_axi_wdata),
        .s00_axi_wstrb(s00_axi_wstrb),
        .s00_axi_wlast(s00_axi_wlast),
        .s00_axi_wuser(s00_axi_wuser),
        .s00_axi_wvalid(s00_axi_wvalid),
        .s00_axi_wready(s00_axi_wready),
        .s00_axi_bid(s00_axi_bid),
        .s00_axi_bresp(s00_axi_bresp),
        .s00_axi_buser(s00_axi_buser),
        .s00_axi_bvalid(s00_axi_bvalid),
        .s00_axi_bready(s00_axi_bready),
        .s00_axi_arid(s00_axi_arid),
        .s00_axi_araddr(s00_axi_araddr),
        .s00_axi_arlen(s00_axi_arlen),
        .s00_axi_arsize(s00_axi_arsize),
        .s00_axi_arburst(s00_axi_arburst),
        .s00_axi_arlock(s00_axi_arlock),
        .s00_axi_arcache(s00_axi_arcache),
        .s00_axi_arprot(s00_axi_arprot),
        .s00_axi_arqos(s00_axi_arqos),
        .s00_axi_arregion(s00_axi_arregion),
        .s00_axi_aruser(s00_axi_aruser),
        .s00_axi_arvalid(s00_axi_arvalid),
        .s00_axi_arready(s00_axi_arready),
        .s00_axi_rid(s00_axi_rid),
        .s00_axi_rdata(s00_axi_rdata),
        .s00_axi_rresp(s00_axi_rresp),
        .s00_axi_rlast(s00_axi_rlast),
        .s00_axi_ruser(s00_axi_ruser),
        .s00_axi_rvalid(s00_axi_rvalid),
        .s00_axi_rready(s00_axi_rready)
    );

    always #5 s00_axi_aclk = ~s00_axi_aclk;

    task automatic init_axi;
        begin
            s00_axi_awid = 0; s00_axi_awaddr = 0; s00_axi_awlen = 0; s00_axi_awsize = 0; s00_axi_awburst = 0;
            s00_axi_awlock = 0; s00_axi_awcache = 0; s00_axi_awprot = 0; s00_axi_awqos = 0; s00_axi_awregion = 0;
            s00_axi_awuser = 0; s00_axi_awvalid = 0; s00_axi_wdata = 0; s00_axi_wstrb = 0; s00_axi_wlast = 0;
            s00_axi_wuser = 0; s00_axi_wvalid = 0; s00_axi_bready = 0; s00_axi_arid = 0; s00_axi_araddr = 0;
            s00_axi_arlen = 0; s00_axi_arsize = 0; s00_axi_arburst = 0; s00_axi_arlock = 0; s00_axi_arcache = 0;
            s00_axi_arprot = 0; s00_axi_arqos = 0; s00_axi_arregion = 0; s00_axi_aruser = 0; s00_axi_arvalid = 0;
            s00_axi_rready = 0;
        end
    endtask

    task automatic load_mem;
        input [1023:0] memfile;
        integer k;
        integer sum;
        reg [31:0] hash;
        begin
            $readmemh(memfile, test_image);
            $display("Loaded %0s", memfile);

            sum = 0;
            hash = 32'h811C9DC5;

            $write("[IMG] first32 = ");
            for (k = 0; k < 32; k = k + 1) begin
                $write("%02x ", test_image[k]);
            end
            $write("\n");

            for (k = 0; k < IMG_SIZE; k = k + 1) begin
                sum = sum + test_image[k];
                hash = hash ^ test_image[k];
                hash = hash * 32'h01000193;
            end

            $write("[IMG] sum=%0d hash=0x%08x last32=", sum, hash);
            for (k = IMG_SIZE-32; k < IMG_SIZE; k = k + 1) begin
                $write("%02x ", test_image[k]);
            end
            $write("\n");
        end
    endtask

    task automatic write_reg32;
        input [9:0] addr;
        input [31:0] data;
        integer t;
        begin
            @(negedge s00_axi_aclk);
            s00_axi_awaddr = addr; s00_axi_awlen = 0; s00_axi_awsize = 3'd2; s00_axi_awburst = 2'b01; s00_axi_awvalid = 1;
            s00_axi_wdata = data; s00_axi_wstrb = 4'hF; s00_axi_wlast = 1; s00_axi_wvalid = 1; s00_axi_bready = 0;
            t = 10000;
            while (!s00_axi_awready) begin @(posedge s00_axi_aclk); #1; t = t - 1; if (!t) $fatal(1, "AWREADY timeout"); end
            t = 10000;
            while (!s00_axi_wready) begin @(posedge s00_axi_aclk); #1; t = t - 1; if (!t) $fatal(1, "WREADY timeout"); end
            @(posedge s00_axi_aclk); #1;
            @(negedge s00_axi_aclk);
            s00_axi_awvalid = 0; s00_axi_wvalid = 0; s00_axi_wlast = 0; s00_axi_wstrb = 0; s00_axi_wdata = 0;
            s00_axi_bready = 1;
            t = 10000;
            while (!s00_axi_bvalid) begin @(posedge s00_axi_aclk); #1; t = t - 1; if (!t) $fatal(1, "BVALID timeout"); end
            if (s00_axi_bresp !== 2'b00) $fatal(1, "BRESP error %b", s00_axi_bresp);
            @(posedge s00_axi_aclk); #1;
            @(negedge s00_axi_aclk);
            s00_axi_bready = 0;
        end
    endtask

    task automatic write_image_packed;
        input [9:0] base;
        integer idx;
        reg [31:0] word;
        begin
            for (idx = 0; idx < IMG_SIZE; idx = idx + 4) begin
                word = {test_image[idx+3], test_image[idx+2], test_image[idx+1], test_image[idx]};
                write_reg32(base + idx[9:0], word);
            end
        end
    endtask

    task automatic read_reg32;
        input [9:0] addr;
        output [31:0] data;
        integer t;
        begin
            @(negedge s00_axi_aclk);
            s00_axi_araddr = addr; s00_axi_arlen = 0; s00_axi_arsize = 3'd2; s00_axi_arburst = 2'b01; s00_axi_arvalid = 1;
            s00_axi_rready = 1;
            t = 10000;
            while (!s00_axi_arready) begin @(posedge s00_axi_aclk); #1; t = t - 1; if (!t) $fatal(1, "ARREADY timeout"); end
            @(posedge s00_axi_aclk); #1;
            @(negedge s00_axi_aclk);
            s00_axi_arvalid = 0;
            t = 10000;
            while (!s00_axi_rvalid) begin @(posedge s00_axi_aclk); #1; t = t - 1; if (!t) $fatal(1, "RVALID timeout"); end
            data = s00_axi_rdata;
            if (s00_axi_rresp !== 2'b00) $fatal(1, "RRESP error %b", s00_axi_rresp);
            @(posedge s00_axi_aclk); #1;
            @(negedge s00_axi_aclk);
            s00_axi_rready = 0;
        end
    endtask

    task automatic readback_image;
        integer idx;
        reg [31:0] data;
        begin
            for (idx = 0; idx < IMG_SIZE; idx = idx + 4) begin
                read_reg32(DMA_BASE + idx[9:0], data);
                if (data[7:0]   !== test_image[idx])   $fatal(1, "readback mismatch byte0 @%0d", idx);
                if (data[15:8]  !== test_image[idx+1]) $fatal(1, "readback mismatch byte1 @%0d", idx);
                if (data[23:16] !== test_image[idx+2]) $fatal(1, "readback mismatch byte2 @%0d", idx);
                if (data[31:24] !== test_image[idx+3]) $fatal(1, "readback mismatch byte3 @%0d", idx);
            end
            $display("Readback PASSED for %0d bytes", IMG_SIZE);
        end
    endtask

        reg [1023:0] memfile;
        reg [31:0] rd;
        integer poll;
        integer done_seen;

    task automatic reset_dut;
        begin
            write_reg32(RESET_BASE, 32'h1);
            repeat (5) @(posedge s00_axi_aclk);
            write_reg32(RESET_BASE, 32'h0);
            repeat (5) @(posedge s00_axi_aclk);
        end
    endtask

    task automatic run_one_image;
        begin
            reset_dut();
            write_image_packed(DMA_BASE);
            readback_image();

            write_reg32(START_BASE, 32'h1);

            done_seen = 0;
            for (poll = 0; poll < 10000 && !done_seen; poll = poll + 1) begin
                read_reg32(DONE_BASE, rd);
                if (rd[0]) done_seen = 1;
                repeat (5) @(posedge s00_axi_aclk);
            end
            if (!done_seen) $fatal(1, "DONE timeout");

            read_reg32(RESULT_BASE, rd);
            $display("RESULT=%0d", rd[3:0]);
        end
    endtask

    initial begin
        s00_axi_aclk = 0;
        s00_axi_aresetn = 0;
        init_axi();
        repeat (10) @(posedge s00_axi_aclk);
        s00_axi_aresetn = 1;
        repeat (5) @(posedge s00_axi_aclk);

        memfile = "digit_3.mem";
        if (!$value$plusargs("MEM=%s", memfile)) $display("Using default MEM=%0s", memfile);
        load_mem(memfile);

        run_one_image();
        $finish;
    end
endmodule
