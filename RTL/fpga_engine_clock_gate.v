`timescale 1ns / 1ps

`define XILINX

// =============================================================================
// Author      : Khanh
// Title       : fpga_engine_clock_gate
// Description : Glitchless FPGA clock gating wrapper for the shared engine.
// =============================================================================
module fpga_engine_clock_gate (
    input  wire clk_in,
    input  wire ce_in,
    output wire clk_out
);

`ifdef XILINX
    // True FPGA clock gating for Xilinx devices.
    // BUFGCE is glitchless and uses dedicated global clock routing.
    BUFGCE u_bufgce_engine (
        .I  (clk_in),
        .CE (ce_in),
        .O  (clk_out)
    );
`else
    // Simulation / non-Xilinx fallback.
    // This is NOT true clock gating, only for portable simulation.
    assign clk_out = clk_in;
`endif

endmodule