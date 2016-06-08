`timescale 1ns/100ps

module LFSR_tb;
 
 // Inputs
 reg clock;
 reg reset;
 
 // Outputs
 wire [12:0] rnd;
 
 // Instantiate the Unit Under Test (UUT)
 LFSR uut (
  .clock(clock),
  .reset(reset),
  .rnd(rnd)
 );
  
 initial begin
  clock = 0;
  forever
   #5 clock = ~clock;
  end
   
 initial begin
  // Initialize Inputs
   
  reset = 0;
 
  // Wait 100 ns for global reset to finish
  #10;
      reset = 1;
  #20;
  reset = 0;
  // Add stimulus here
 
 end
  
 initial begin
 $display("clock rnd");
 $monitor("%b,%b", clock, rnd);
 end     
endmodule