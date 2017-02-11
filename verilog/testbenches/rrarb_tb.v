`timescale 1ns/100ps
module rrarb_tb;

   localparam NR   = 4;
   localparam PIPE = 0;

   reg clk;
   reg reset;
   reg [NR-1:0] req;
   reg stall;
   wire [NR-1:0] vgnt;
   wire eval;
   wire [2-1:0] egnt;

   rrarb #(
      .NR  (NR  ),
      .PIPE(PIPE)
   ) dut (
      .clk  (clk  ),
      .reset(reset),
      .req  (req  ),
      .stall(stall),
      .vgnt (vgnt ),
      .eval (eval ),
      .egnt (egnt )
   );
   
   initial
   begin
      clk = 0;
      reset = 1;
      req = 0;
      stall = 0;
      
      #20 reset = 0;
      #5
      
      @(negedge clk)
      req = 4'b0110;
      
      @(negedge clk)
      req = 4'b1110;
      @(negedge clk)
      req = 4'b1111;
      @(negedge clk)
      req = 4'b1111;
      stall = 1;
      @(negedge clk)
      req = 4'b1111;
      @(negedge clk)
      req = 4'b1111;
      stall = 0;
      @(negedge clk)
      req = 4'b0001;
      stall = 1;
      @(negedge clk)
      req = 4'b0010;
      @(negedge clk)
      req = 4'b0110;
      @(negedge clk)
      req = 4'b0111;
      @(negedge clk)
      req = 4'b1001;
      @(negedge clk)
      req = 4'b0001;
      @(negedge clk)
      req = 4'b1001;
      @(negedge clk)
      req = 4'b0101;
      @(negedge clk)
      req = 4'b0011;
      @(negedge clk)
      req = 4'b0001;
      stall = 0;
      @(negedge clk)
      req = 4'b1000;
      @(negedge clk)
      req = 4'b0101;
      stall = 1;
      @(negedge clk)
      req = 4'b0010;
      @(negedge clk)
      req = 4'b0011;
      @(negedge clk)
      req = 4'b1101;
      @(negedge clk)
      req = 4'b1111;
      #10 $finish;
   end

   always
      #5 clk = ! clk;

endmodule
