`timescale 1ns/100ps
module phold_tb();

reg clk, rst_n;
wire [13:0] gvt;
wire rtn_vld;
phold DUT(clk, rst_n, gvt, rtn_vld);




initial begin
 clk = 0;
 forever #5 clk = ~clk;
end

initial begin
 rst_n = 0;
 #20
 rst_n = 1;
 
 @(posedge rtn_vld)
 rst_n = 0;
 
//	#20 $finish;
end 

endmodule
