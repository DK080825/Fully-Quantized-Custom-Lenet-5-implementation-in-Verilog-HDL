module input_bank_ctrl #(
    parameter ADDR_WIDTH = 10,
    parameter INPUT_WIDTH = 28,
    parameter INPUT_HEIGHT = 28
)(
    input  logic mnist_wren,
    input  logic [ADDR_WIDTH-1:0] mnist_waddr,
    
    output logic we_a,
    output logic we_b,
    output logic [ADDR_WIDTH-1:0] waddr_a,
    output logic [ADDR_WIDTH-1:0] waddr_b
);

    logic [5:0] row;
    logic [5:0] col;
    
    always_comb begin
        // address decode
        row = mnist_waddr / INPUT_WIDTH;
        col = mnist_waddr % INPUT_WIDTH;

        // default assignments
        we_a   = 0;
        we_b   = 0;
        waddr_a = 0;
        waddr_b = 0;

        // Bank A : rows 0–13
        if (row < 14) begin
            we_a   = mnist_wren;
            waddr_a = row * INPUT_WIDTH + col;
        end

        // Bank B : rows 12–27
        if (row >= 12) begin
            we_b   = mnist_wren;
            waddr_b = (row - 12) * INPUT_WIDTH + col;
        end
    end

endmodule