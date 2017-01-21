`timescale 1ns/100ps
module phold_tb;

   localparam SIM_END_TIME = 2000;  // Target GVT value when process returns
   localparam NUM_MC_PORTS    = 1;
   localparam MC_RTNCTL_WIDTH = 32;
   localparam TIME_WID = 16;
   localparam RAM_DEPTH = 512;
   localparam NUM_INIT_EVENTS = 64;
   localparam LP_MASK = 8'hFF;
   
   reg clk;
   reg rst_n;
   reg [47:0] addr;
   wire [TIME_WID-1:0] gvt;
   wire rtn_vld;
   wire mc_rq_vld;
   wire [2:0] mc_rq_cmd;
   wire [3:0] mc_rq_scmd;
   wire [47:0] mc_rq_vadr;
   wire [1:0] mc_rq_size;
   wire [MC_RTNCTL_WIDTH-1:0] mc_rq_rtnctl;
   wire [63:0] mc_rq_data;
   wire mc_rq_flush;
   wire mc_rq_stall;
   wire mc_rs_vld;
   wire [2:0] mc_rs_cmd;
   wire [3:0] mc_rs_scmd;
   wire [MC_RTNCTL_WIDTH-1:0] mc_rs_rtnctl;
   wire [63:0] mc_rs_data;
   wire mc_rs_stall;
   
   
   wire [63:0] total_cycles;
   wire [63:0] total_events;
   wire [63:0] total_stalls;
   wire [63:0] total_antimsg;

   phold #(
      .NUM_MC_PORTS   (NUM_MC_PORTS   ),
      .MC_RTNCTL_WIDTH(MC_RTNCTL_WIDTH)
   ) dut (
      .clk         (clk         ),
      .rst_n       (rst_n       ),
      .sim_end     ( SIM_END_TIME ),
      .num_init_events ( NUM_INIT_EVENTS ),
      .lp_mask     ( LP_MASK ),
      .addr        (addr        ),
      .gvt         (gvt         ),
      
      .total_cycles ( total_cycles),
      .total_events ( total_events),
      .total_stalls ( total_stalls),
      .total_antimsg ( total_antimsg),
      
      .rtn_vld     (rtn_vld     ),
      .mc_rq_vld   (mc_rq_vld   ),
      .mc_rq_cmd   (mc_rq_cmd   ),
      .mc_rq_scmd  (mc_rq_scmd  ),
      .mc_rq_vadr  (mc_rq_vadr  ),
      .mc_rq_size  (mc_rq_size  ),
      .mc_rq_rtnctl(mc_rq_rtnctl),
      .mc_rq_data  (mc_rq_data  ),
      .mc_rq_flush (mc_rq_flush ),
      .mc_rq_stall (mc_rq_stall ),
      .mc_rs_vld   (mc_rs_vld   ),
      .mc_rs_cmd   (mc_rs_cmd   ),
      .mc_rs_scmd  (mc_rs_scmd  ),
      .mc_rs_rtnctl(mc_rs_rtnctl),
      .mc_rs_data  (mc_rs_data  ),
      .mc_rs_stall (mc_rs_stall )
      );
   
   dummy_mc #(
      .MC_RTNCTL_WIDTH(MC_RTNCTL_WIDTH),
      .RAM_DEPTH      (RAM_DEPTH      )
   ) u_dummy_mc (
      .clk         (clk         ),
      .mc_rq_vld   (mc_rq_vld   ),
      .mc_rq_cmd   (mc_rq_cmd   ),
      .mc_rq_scmd  (mc_rq_scmd  ),
      .mc_rq_vadr  (mc_rq_vadr  ),
      .mc_rq_size  (mc_rq_size  ),
      .mc_rq_rtnctl(mc_rq_rtnctl),
      .mc_rq_data  (mc_rq_data  ),
      .mc_rq_flush (mc_rq_flush ),
      .mc_rq_stall (mc_rq_stall ),
      .mc_rs_vld   (mc_rs_vld   ),
      .mc_rs_cmd   (mc_rs_cmd   ),
      .mc_rs_scmd  (mc_rs_scmd  ),
      .mc_rs_rtnctl(mc_rs_rtnctl),
      .mc_rs_data  (mc_rs_data  ),
      .mc_rs_stall (mc_rs_stall ),
      .reset       (!rst_n      )
   );
   
   initial
   begin
      clk = 0;
      rst_n = 0;
      addr = 0;
      
      #20
      rst_n = 1;
      
      @(posedge rtn_vld)
      $display("Simulation ended at GVT = %d", gvt);
      $display("Total cycles = %d", total_cycles);
      $display("Total events = %d", total_events);
      $display("Total anti-messages = %d", total_antimsg );
      $display("Total stalls = %d", total_stalls - (7*total_events) );
      $finish;
   end
   
   always
      #5 clk = ! clk;

endmodule
