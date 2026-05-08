// =============================================================================
// Author      : Giau
// Title       : input_bank_ctrl
// Description : Decodes MNIST-style write addresses into overlapping ping-pong
//               input-bank write enables and addresses.
// =============================================================================
module input_bank_ctrl #(
    parameter ADDR_WIDTH   = 10,
    parameter INPUT_WIDTH  = 28,
    parameter INPUT_HEIGHT = 28
)(
    input  wire                     mnist_wren_in,
    input  wire [ADDR_WIDTH-1:0]    mnist_waddr_in,

    output reg                       we_a_out,
    output reg                       we_b_out,
    output reg [ADDR_WIDTH-1:0]      waddr_a_out,
    output reg [ADDR_WIDTH-1:0]      waddr_b_out
);

    reg [5:0] row_r;
    reg [5:0] col_r;

    always @(*) begin
        row_r = mnist_waddr_in / INPUT_WIDTH;
        col_r = mnist_waddr_in % INPUT_WIDTH;

        we_a_out    = 1'b0;
        we_b_out    = 1'b0;
        waddr_a_out = {ADDR_WIDTH{1'b0}};
        waddr_b_out = {ADDR_WIDTH{1'b0}};

        if (row_r < 14) begin
            we_a_out    = mnist_wren_in;
            waddr_a_out = row_r * INPUT_WIDTH + col_r;
        end

        if (row_r >= 12) begin
            we_b_out    = mnist_wren_in;
            waddr_b_out = (row_r - 12) * INPUT_WIDTH + col_r;
        end
    end

endmodule