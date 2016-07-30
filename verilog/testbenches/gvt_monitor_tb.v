`timescale 1 ns / 100 ps

module gvt_monitor_tb;

   localparam                         NUM_CORE   = 8;
   localparam                         TIME_WID   = 16;

   reg                                clk;
   reg        [TIME_WID*NUM_CORE-1:0] core_times;
   reg        [NUM_CORE-1:0]          core_vld;
   reg        [TIME_WID-1:0]          next_event;
   wire       [TIME_WID-1:0]          gvt;

   gvtmonitor #(
      .NUM_CORE(NUM_CORE),
      .TIME_WID(TIME_WID)
   ) dut (
      .core_times(core_times),
      .core_vld  (core_vld  ),
      .next_event(next_event),
      .gvt       (gvt       )
   );

   initial
   begin
      clk = 0;
      core_times = 0;
      core_vld = 0;
      next_event = 0;
      
      next_event = 16'h25;
      @(posedge clk)
      #5 if(gvt != 16'h25) $display("ERROR: unexpected gvt value");
      
      core_vld[1] = 1;
      core_times[TIME_WID*1 +: TIME_WID] = 16'h23;
      @(posedge clk)
      #5 if(gvt != 16'h23) $display("ERROR: unexpected gvt value");
      
      core_vld[2] = 1;
      core_times[TIME_WID*2 +: TIME_WID] = 16'h22;
      @(posedge clk)
      #5 if(gvt != 16'h22) $display("ERROR: unexpected gvt value");
      
      core_vld[0] = 1;
      core_times[TIME_WID*0 +: TIME_WID] = 16'h26;
      @(posedge clk)
      #5 if(gvt != 16'h22) $display("ERROR: unexpected gvt value");
      
      core_vld[3] = 1;
      core_times[TIME_WID*3 +: TIME_WID] = 16'h18;
      @(posedge clk)
      #5 if(gvt != 16'h18) $display("ERROR: unexpected gvt value");
      
      next_event = 16'h15;
      @(posedge clk)
      #5 if(gvt != 16'h15) $display("ERROR: unexpected gvt value");
      
      core_vld[6] = 1;
      core_times[TIME_WID*6 +: TIME_WID] = 16'h12;
      @(posedge clk)
      #5 if(gvt != 16'h12) $display("ERROR: unexpected gvt value");
      
      #5 $finish;
   end

   always
      #5 clk = ! clk;

endmodule