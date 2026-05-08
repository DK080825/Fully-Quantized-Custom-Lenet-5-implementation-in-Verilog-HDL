`timescale 1ns / 1ps

module adder_tree_signed #(
    parameter N     = 6,
    parameter IN_W  = 18,
    parameter OUT_W = 0
)(
    din,
    dout
);

/*function integer clog2;
    input integer value;
    integer i;
    begin
        value = value - 1;
        for (i = 0; value > 0; i = i + 1)
            value = value >> 1;
        if (i == 0)
            clog2 = 1;
        else
            clog2 = i;
    end
endfunction*/

localparam CALC_OUT_W = IN_W + $clog2(N);
localparam ACT_OUT_W  = (OUT_W == 0) ? CALC_OUT_W : OUT_W;
localparam NEXT_N     = (N + 1) / 2;
localparam MID_W      = IN_W + 1;

input  signed [N*IN_W-1:0] din;
output signed [ACT_OUT_W-1:0] dout;
wire   signed [ACT_OUT_W-1:0] dout;

generate
    if (N == 1) begin : GEN_BASE1
        assign dout = {{(ACT_OUT_W-IN_W){din[IN_W-1]}}, din[IN_W-1:0]};
    end
    else if (N == 2) begin : GEN_BASE2
        assign dout = $signed(din[IN_W-1:0]) + $signed(din[2*IN_W-1:IN_W]);
    end
    else begin : GEN_RECURSE
        wire signed [NEXT_N*MID_W-1:0] pair_sum;
        wire signed [ACT_OUT_W-1:0] sub_dout;

        genvar i;
        for (i = 0; i < N/2; i = i + 1) begin : GEN_PAIR
            assign pair_sum[(i+1)*MID_W-1:i*MID_W] =
                $signed(din[(2*i+1)*IN_W-1:(2*i)*IN_W]) +
                $signed(din[(2*i+2)*IN_W-1:(2*i+1)*IN_W]);
        end

        if (N % 2) begin : GEN_ODD
            assign pair_sum[(N/2+1)*MID_W-1:(N/2)*MID_W] =
                {{(MID_W-IN_W){din[N*IN_W-1]}}, din[N*IN_W-1:(N-1)*IN_W]};
        end

        adder_tree_signed #(
            .N    (NEXT_N),
            .IN_W (MID_W),
            .OUT_W(ACT_OUT_W)
        ) u_subtree (
            .din (pair_sum),
            .dout(sub_dout)
        );

        assign dout = sub_dout;
    end
endgenerate

endmodule