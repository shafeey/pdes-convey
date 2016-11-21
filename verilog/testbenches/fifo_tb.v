`timescale 1ns/100ps
module fifo_tb;

   localparam width = 32;

   reg rst;
   reg clk;
   reg rd_en;
   wire [(width-1):0] dout;
   wire empty;
   reg wr_en;
   reg [(width-1):0] din;
   wire full;
   wire [4:0] count;

   fwft_fifo #(
      .WIDTH(width)
   ) dut (
      .rst      (rst      ),
      .clk      (clk      ),
      .rd_en    (rd_en    ),
      .dout     (dout     ),
      .data_count(count),
      .empty    (empty    ),
      .wr_en    (wr_en    ),
      .din      (din      ),
      .full     (full     )
   );
   
   initial
   begin
      rst = 1;
      clk = 0;
      rd_en = 0;
      wr_en = 0;
      din = 0;
      
      #10 rst = 0;
      
      #40
      din = 'h12;
      wr_en = 1;
      
      #10
      rd_en = 1;
      wr_en = 0;
      #10
      rd_en = 0;
      
      #20
      din = 'h25;
      wr_en = 1;
      #10
      wr_en = 0;
      #20
      wr_en = 1;
      din = 'h37;
      #10
      din = 'h11;
      #10
      wr_en = 0;
      
      #20
      rd_en = 1;
      #30
      rd_en = 0;
      
      #10
      din = 'h11;
      wr_en = 1;
      #10 din = 'h22;
      #10 din = 'h33;
      #10 din = 'h44;
      #10 din = 'h55;
      #10 din = 'h66;
      #10 din = 'h77;
      #10 din = 'h88;
      #10 din = 'h99;
      #10 din = 'h15;
      #10 din = 'h26;
      #10 din = 'h54;
      #10 din = 'h87;
      #10 din = 'h65;
      #10 din = 'h32;
      #10 din = 'h54;
      #10 din = 'h58;
      #10 din = 'h56;
      #10 din = 'h14;
      #10
      wr_en = 0;
      #10
      rd_en = 1;
      #200
      rd_en = 0;
  
      
      
   end

   always
      #5 clk = ! clk;

endmodule
