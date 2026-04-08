`timescale 1ns / 1ps
module lutrom_sync #(
    parameter int WIDTH   = 48,
    parameter int DEPTH   = 9,
    parameter int ADDR_W  = 4,
    parameter string MEMFILE = ""
)(
    input  logic               clk,
    input  logic               en,
    input  logic [ADDR_W-1:0]  addr,
    output logic [WIDTH-1:0]   q
);
    (* rom_style = "distributed", ram_style = "distributed" *)
    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [WIDTH-1:0] q_reg;
    initial begin : init_rom
        integer k;
        for (k = 0; k < DEPTH; k = k + 1)
            mem[k] = '0;
        if (MEMFILE != "")
            $readmemh(MEMFILE, mem);
    end

    always_ff @(posedge clk) begin
        if (en) begin
            q_reg <= mem[addr];
            q     <= q_reg;
        end
    end
endmodule
