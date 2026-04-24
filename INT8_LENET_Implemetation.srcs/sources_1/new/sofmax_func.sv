// Author: Do Khanh
// School: UIT
// Description: Softmax function/approximation module. It transforms logits into normalized probability-like outputs using hardware-oriented arithmetic/lookup strategies suitable for FPGA inference.

`timescale 1ns / 1ps

module sofmax_func #(
    parameter DATA_WIDTH = 8
)(
    input  logic                  clk,
    input  logic                  run,
    input  logic [DATA_WIDTH-1:0] data_in0,
    input  logic [DATA_WIDTH-1:0] data_in1,
    input  logic [DATA_WIDTH-1:0] data_in2,
    input  logic [DATA_WIDTH-1:0] data_in3,
    input  logic [DATA_WIDTH-1:0] data_in4,
    input  logic [DATA_WIDTH-1:0] data_in5,
    input  logic [DATA_WIDTH-1:0] data_in6,
    input  logic [DATA_WIDTH-1:0] data_in7,
    input  logic [DATA_WIDTH-1:0] data_in8,
    input  logic [DATA_WIDTH-1:0] data_in9,

    output logic [3:0] hex_out
);

    logic [DATA_WIDTH-1:0] s1_val [4:0];
    logic [3:0]            s1_idx [4:0];

    logic [DATA_WIDTH-1:0] s2_val [2:0];
    logic [3:0]            s2_idx [2:0];

    logic [DATA_WIDTH-1:0] s3_val;
    logic [3:0]            s3_idx;

    // stage 1: pairwise compare
    always_comb begin
        if (data_in0 >= data_in1) begin
            s1_val[0] = data_in0;
            s1_idx[0] = 4'd0;
        end else begin
            s1_val[0] = data_in1;
            s1_idx[0] = 4'd1;
        end

        if (data_in2 >= data_in3) begin
            s1_val[1] = data_in2;
            s1_idx[1] = 4'd2;
        end else begin
            s1_val[1] = data_in3;
            s1_idx[1] = 4'd3;
        end

        if (data_in4 >= data_in5) begin
            s1_val[2] = data_in4;
            s1_idx[2] = 4'd4;
        end else begin
            s1_val[2] = data_in5;
            s1_idx[2] = 4'd5;
        end

        if (data_in6 >= data_in7) begin
            s1_val[3] = data_in6;
            s1_idx[3] = 4'd6;
        end else begin
            s1_val[3] = data_in7;
            s1_idx[3] = 4'd7;
        end

        if (data_in8 >= data_in9) begin
            s1_val[4] = data_in8;
            s1_idx[4] = 4'd8;
        end else begin
            s1_val[4] = data_in9;
            s1_idx[4] = 4'd9;
        end
    end

    // stage 2
    always_comb begin
        if (s1_val[0] >= s1_val[1]) begin
            s2_val[0] = s1_val[0];
            s2_idx[0] = s1_idx[0];
        end else begin
            s2_val[0] = s1_val[1];
            s2_idx[0] = s1_idx[1];
        end

        if (s1_val[2] >= s1_val[3]) begin
            s2_val[1] = s1_val[2];
            s2_idx[1] = s1_idx[2];
        end else begin
            s2_val[1] = s1_val[3];
            s2_idx[1] = s1_idx[3];
        end

        s2_val[2] = s1_val[4];
        s2_idx[2] = s1_idx[4];
    end

    // stage 3
    always_comb begin
        if (s2_val[0] >= s2_val[1]) begin
            s3_val = s2_val[0];
            s3_idx = s2_idx[0];
        end else begin
            s3_val = s2_val[1];
            s3_idx = s2_idx[1];
        end

        if (s2_val[2] >= s3_val) begin
            s3_idx = s2_idx[2];
        end
    end

    always_ff @(posedge clk) begin
        if (!run)
            hex_out <= 4'hF;
        else
            hex_out <= s3_idx;
    end

endmodule