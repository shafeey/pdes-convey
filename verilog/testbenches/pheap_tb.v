`timescale 1ns/100ps
module pheap_tb;

   localparam WIDTH   = 32;
   localparam CMP_WID = 32;
   localparam DEPTH   = 5;

   reg clk;
   reg enq;
   reg deq;
   reg [WIDTH-1:0] inp_data;
   wire [WIDTH-1:0] out_data;
   wire [DEPTH-1:0] elem_cnt;
   wire full;
   wire empty;
   wire ready;
   reg rst_n;
   
   
   pheap #(
      .WIDTH  (WIDTH  ),
      .CMP_WID(CMP_WID),
      .DEPTH  (DEPTH  )
   ) dut (
      .clk     (clk     ),
      .enq     (enq     ),
      .deq     (deq     ),
      .inp_data(inp_data),
      .out_data(out_data),
      .elem_cnt(elem_cnt),
      .full    (full    ),
      .empty   (empty   ),
      .ready   (ready   ),
      .rst_n   (rst_n   )
   );
   
   initial
   begin
      clk = 0;
      enq = 0;
      deq = 0;
      inp_data = 0;
      rst_n = 0;
      
      #20 rst_n = 1;
      #5;
      
      #10
      enq = 1;
      inp_data = 9;
      #10 enq = 0;
      
      #10
      enq = 1;
      inp_data = 7;
      #10 enq = 0;
      
      #20;
      
       #10
      enq = 1;
      inp_data = 3;
      #10 enq = 0;
       #10
      enq = 1;
      inp_data = 8;
      #10 enq = 0;
       #30
      enq = 1;
      inp_data = 4;
      #10 enq = 0;
       #10
      enq = 1;
      inp_data = 15;
      #10 enq = 0;
       #10
      enq = 1;
      inp_data = 1;
      #10 enq = 0;
       
      #40;
      
      #10 deq = 1;
      #10 deq = 0;
      
      #10 deq = 1;
      #10 deq = 0;
      
      #10 deq = 1;
      #10 deq = 0;
      
      #10 deq = 1;
      #10 deq = 0;
      
      #10 deq = 1;
      #10 deq = 0;
      
      #10 deq = 1;
      #10 deq = 0;
      
      #10 deq = 1;
      #10 deq = 0;
      
       
//      enq = 1;
//      inp_data = 13;
//      #10 enq = 0;
//       #10
//      enq = 1;
//      inp_data = 8;
//      #10 enq = 0;
//       #10
//      enq = 1;
//      inp_data = 14;
//      #10 enq = 0;
//       #10
//      enq = 1;
//      inp_data = 4;
//      #10 enq = 0;
//       #10
//      enq = 1;
//      inp_data = 6;
//      #10 enq = 0;
//       #10
//      enq = 1;
//      inp_data = 7;
//      #10 enq = 0;
//       #10
//      enq = 1;
//      inp_data = 12;
//      #10 enq = 0;
       
      
      #40 $finish;
      
   end

   always
      #5 clk = ! clk;

endmodule
