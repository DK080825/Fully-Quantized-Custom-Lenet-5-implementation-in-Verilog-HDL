`timescale 1ns / 1ps

module sofmax_func #(
    parameter DATA_WIDTH = 8
)
(
    input logic clk,
    input logic run,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in0,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in1,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in2,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in3,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in4,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in5,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in6,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in7,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in8,
    input logic signed [DATA_WIDTH -1 : 0 ] data_in9,
    
    output logic [3:0] hex_out
    );
    
    logic signed [DATA_WIDTH-1:0] max_pair1, max_pair2, max_pair3, max_pair4, max_pair5;
    
    assign max_pair1 = data_in0 > data_in1? data_in0 : data_in1;
    assign max_pair2 = data_in2 > data_in3? data_in2 : data_in3;
    assign max_pair3 = data_in4 > data_in5? data_in4 : data_in5;
    assign max_pair4 = data_in6 > data_in7? data_in6 : data_in7;
    assign max_pair5 = data_in8 > data_in9? data_in8 : data_in9;
    
    logic signed [DATA_WIDTH-1:0] max_pair1_p2, max_pair2_p2, max_pair3_p2;
    
    assign max_pair1_p2 = max_pair1 > max_pair2? max_pair1 : max_pair2;
    
    assign max_pair2_p2 = max_pair3 > max_pair4? max_pair3 : max_pair4;
    assign max_pair3_p2 = max_pair5 > max_pair2_p2? max_pair5 : max_pair2_p2;
    
    logic signed [DATA_WIDTH-1:0] final_max;
    assign final_max = max_pair1_p2 > max_pair3_p2 ? max_pair1_p2 : max_pair3_p2;
    
    always @(posedge clk) begin
        if(!run) begin
            hex_out <= 4'b1111;
        end
        else begin 
        case(final_max)
            data_in0: hex_out <= 4'd0;
            data_in1: hex_out <= 4'd1;
            data_in2: hex_out <= 4'd2;
            data_in3: hex_out <= 4'd3;
            data_in4: hex_out <= 4'd4;
            data_in5: hex_out <= 4'd5;
            data_in6: hex_out <= 4'd6;
            data_in7: hex_out <= 4'd7;                       
            data_in8: hex_out <= 4'd8;                       
            data_in9: hex_out <= 4'd9;      
            default: hex_out <= 4'hf;
        endcase
        end                
    end
     
endmodule
