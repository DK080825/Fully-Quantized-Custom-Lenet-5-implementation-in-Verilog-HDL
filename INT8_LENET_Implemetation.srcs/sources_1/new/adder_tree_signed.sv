// Author: Do Khanh
// School: UIT
// Description: Signed adder-tree reduction module. It combines multiple signed partial products through a balanced tree structure to reduce critical-path delay and provide efficient summation for convolution or dense computations.

`timescale 1ns / 1ps
module adder_tree_signed #(
    parameter int N     = 6,
    parameter int IN_W  = 18,
    parameter int OUT_W = IN_W + $clog2(N)
)(
    input  logic signed [IN_W-1:0]  din [N],
    output logic signed [OUT_W-1:0] dout
);

    localparam int NEXT_N = (N + 1) / 2;
    localparam int MID_W  = IN_W + 1;

    generate
        if (N == 1) begin : GEN_BASE1
            assign dout = $signed(din[0]);
        end
        else if (N == 2) begin : GEN_BASE2
            assign dout = $signed(din[0]) + $signed(din[1]);
        end
        else begin : GEN_RECURSE
            logic signed [MID_W-1:0] pair_sum [NEXT_N-1:0];
            logic signed [OUT_W-1:0] sub_dout;

            genvar i;
            for (i = 0; i < N/2; i++) begin : GEN_PAIR
                assign pair_sum[i] = $signed(din[2*i]) + $signed(din[2*i+1]);
            end

            if (N % 2) begin : GEN_ODD
                assign pair_sum[N/2] = $signed(din[N-1]);
            end

            adder_tree_signed #(
                .N    (NEXT_N),
                .IN_W (MID_W),
                .OUT_W(OUT_W)
            ) u_subtree (
                .din (pair_sum),
                .dout(sub_dout)
            );

            assign dout = sub_dout;
        end
    endgenerate

endmodule