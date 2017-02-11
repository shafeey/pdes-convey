`timescale 1 ns/ 100 ps
module core_monitor_tb;

   localparam NUM_CORE = 4;
   localparam NUM_LP   = 8;
   localparam TIME_WID = 16;
   localparam MSG_WID  = 32;
   localparam NB_CORE = $clog2(NUM_CORE);

   reg clk;
   reg [MSG_WID-1:0] msg;
   reg sent_msg_vld;
   reg rcv_msg_vld;
   reg [NB_CORE-1:0] core_id;
   wire [NUM_CORE-1:0] stall;
   reg reset;

   core_monitor #(
      .NUM_CORE(NUM_CORE),
      .NUM_LP  (NUM_LP  ),
      .TIME_WID(TIME_WID),
      .MSG_WID (MSG_WID )
   ) dut (
      .clk         (clk         ),
      .msg         (msg         ),
      .sent_msg_vld(sent_msg_vld),
      .rcv_msg_vld (rcv_msg_vld ),
      .core_id     (core_id     ),
      .stall       (stall       ),
      .reset       (reset       )
   );
   
   initial
   begin
      clk = 0;
      msg = 0;
      sent_msg_vld = 0;
      rcv_msg_vld = 0;
      core_id = 0;
      reset = 1;
      
      #20
      reset = 0;
      
      @(posedge clk)
      msg = {16'd1, 16'd25};
      core_id = 0;
      sent_msg_vld = 1;
      rcv_msg_vld = 0;
      
      @(posedge clk)
      msg = {16'd2, 16'd35};
      core_id = 2;
      sent_msg_vld = 1;
      rcv_msg_vld = 0;
      
      @(posedge clk)
      msg = {16'd3, 16'd40};
      core_id = 3;
      sent_msg_vld = 1;
      rcv_msg_vld = 0;
      
      @(posedge clk)
      msg = {16'd2, 16'd45};
      core_id = 1;
      sent_msg_vld = 1;
      rcv_msg_vld = 0;
      
      @(posedge clk)
      msg = {16'd3, 16'd55};
      core_id = 3;
      sent_msg_vld = 0;
      rcv_msg_vld = 1;
      
      @(posedge clk)
      msg = {16'd2, 16'd40};
      core_id = 3;
      sent_msg_vld = 1;
      rcv_msg_vld = 0;
      
      @(posedge clk)
      msg = {16'd2, 16'd65};
      core_id = 2;
      sent_msg_vld = 0;
      rcv_msg_vld = 1;
      
      @(posedge clk)
      msg = {16'd1, 16'd25};
      core_id = 2;
      sent_msg_vld = 1;
      rcv_msg_vld = 0;
      
      @(posedge clk)
      msg = {16'd1, 16'd25};
      core_id = 0;
      sent_msg_vld = 0;
      rcv_msg_vld = 1;
      
      @(posedge clk)
      msg = {16'd1, 16'd25};
      core_id = 2;
      sent_msg_vld = 0;
      rcv_msg_vld = 1;
      
      #10
      $finish;
   end
   
   always@(posedge clk)
      $display("%b=>%1d::%-5d, \t%b=>%1d::%-5d, \t%b=>%1d::%-5d, \t%b=>%1d::%-5d,\t%4b",
                  dut.core_active[3], dut.core_LP_id[3], dut.core_times[3],
                  dut.core_active[2], dut.core_LP_id[2], dut.core_times[2],
                  dut.core_active[1], dut.core_LP_id[1], dut.core_times[1],
                  dut.core_active[0], dut.core_LP_id[0], dut.core_times[0],
                  stall);

   always
      #5 clk = ! clk;

endmodule
