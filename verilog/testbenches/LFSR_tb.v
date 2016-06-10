`timescale 1ns/100ps

module LFSR_tb;
 
 // Inputs
reg clk;
reg reset_n;
reg next;
wire [15:0] seed;
 
 // Outputs
wire [7:0] rnd;
 
 // Instantiate the Unit Under Test (UUT)
 LFSR uut (
  .clk(clk),
  .rst_n(reset_n),
  .next(next),
  .seed(seed),
  .rnd(rnd)
 );
  
assign seed = ~(16'b0);

initial begin
	clk = 0;
	forever
    #5 clk = ~clk;
end
   
initial begin
	// Initialize Inputs
	reset_n = 1;
	next = 0;

	// Wait 100 ns for global reset_n to finish
	#10;
	  reset_n = 0;
	#25;
	reset_n = 1;

	// Stimulus here
	#20 next = 1;
	#50 next = 0;
	#50 next = 1;
	
	#500 $finish;

end
 
initial begin
	$display("clk rnd");
	$monitor("%b,%b", clk, rnd);
end     

endmodule