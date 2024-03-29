/*****************************************************************************/
//
// Module      : cae_pers.vpp
// Revision    :  Revision: 1.15  
// Last Modified On:  Date: 2013-10-29 19:02:06  
// Last Modified By:  Author: gedwards  
//
//-----------------------------------------------------------------------------
//
// Original Author : gedwards
// Created On      : Wed Oct 10 09:26:08 2007
//
//-----------------------------------------------------------------------------
//
// Description     : Sample PDK Vector Add Personality
//
//                   Top-level of vadd personality.  For a complete list of 
//                   optional ports, see 
//                   /opt/convey/pdk2/<rev>/<platform>/doc/cae_pers.v
//
//-----------------------------------------------------------------------------
//
// Copyright (c) 2007-2014 : created by Convey Computer Corp. This model is the
// confidential and proprietary property of Convey Computer Corp.
//
/*****************************************************************************/
/*  Id: cae_pers.vpp,v 1.15 2013-10-29 19:02:06 gedwards Exp   */

`timescale 1 ns / 1 ps

`include "pdk_fpga_defines.vh"

(* keep_hierarchy = "true" *)
module cae_pers #(
   parameter    NUM_MC_PORTS = 16,
   parameter    RTNCTL_WIDTH = 32
) (
   //
   // Clocks and Resets
   //
   input        clk,        // Personalitycore clock
   input        clkhx,      // half-rate clock
   input        clk2x,      // 2x rate clock
   input        i_reset,    // global reset synchronized to clk

   //
   // Dispatch Interface
   //
   input                disp_inst_vld,
   input  [4:0]         disp_inst,
   input  [17:0]        disp_aeg_idx,
   input                disp_aeg_rd,
   input                disp_aeg_wr,
   input  [63:0]        disp_aeg_wr_data,

   output [17:0]        disp_aeg_cnt,
   output [15:0]        disp_exception,
   output               disp_idle,
   output               disp_rtn_data_vld,
   output [63:0]        disp_rtn_data,
   output               disp_stall,

   //
   // MC Interface(s)
   //
   output [NUM_MC_PORTS*1-1 :0]         mc_rq_vld,
   output [NUM_MC_PORTS*RTNCTL_WIDTH-1:0]         mc_rq_rtnctl,
   output [NUM_MC_PORTS*64-1:0]         mc_rq_data,
   output [NUM_MC_PORTS*48-1:0]         mc_rq_vadr,
   output [NUM_MC_PORTS*2-1 :0]         mc_rq_size,
   output [NUM_MC_PORTS*3-1 :0]         mc_rq_cmd,
   output [NUM_MC_PORTS*4-1 :0]         mc_rq_scmd,
   input  [NUM_MC_PORTS*1-1 :0]         mc_rq_stall,
   
   input  [NUM_MC_PORTS*1-1 :0]         mc_rs_vld,
   input  [NUM_MC_PORTS*3-1 :0]         mc_rs_cmd,
   input  [NUM_MC_PORTS*4-1 :0]         mc_rs_scmd,
   input  [NUM_MC_PORTS*64-1:0]         mc_rs_data,
   input  [NUM_MC_PORTS*RTNCTL_WIDTH-1:0]         mc_rs_rtnctl,
   output [NUM_MC_PORTS*1-1 :0]         mc_rs_stall,

   // Write flush 
   output [NUM_MC_PORTS*1-1 :0]         mc_rq_flush,
   input  [NUM_MC_PORTS*1-1 :0]         mc_rs_flush_cmplt,

   //
   // AE-to-AE Interface not used
   //

   //
   // Management/Debug Interface
   //
   input                csr_wr_vld,
   input                csr_rd_vld,
   input  [15:0]            csr_address,
   input  [63:0]            csr_wr_data,
   output               csr_rd_ack,
   output [63:0]            csr_rd_data,

   //
   // Miscellaneous
   //
   input  [3:0]     i_aeid
);

`include "pdk_fpga_param.vh"

   //**************************************************************************
   //              PERSONALITY SPECIFIC LOGIC
   //**************************************************************************

   //
   // AEG[0..NA-1] Registers
   //
   localparam NA = 16;
   localparam NB = 4;       // Number of bits to represent NAEG
   localparam AEG_ADDR_A1 = 0;  // Array 1 address
   localparam AEG_SIM_END_TIME = 1;   // Simulation end target GVT
   localparam AEG_NUM_INIT_EVENTS = 2;   // Number of initial events
   localparam AEG_CONFIG = 3;    // bits 19:16 = num_mem_access, 7:0 = num_lp_mask
   localparam AEG_COREMASK = 4;    // Number of processing delay cycles
   
   localparam AEG_GVT = 5; // GVT return on AEG[1]
   localparam AEG_TOTAL_CYCLES = 6;
   localparam AEG_TOTAL_EVENTS = 7;
   localparam AEG_TOTAL_STALLS = 8;
   localparam AEG_TOTAL_ANTIMSG = 9;
   localparam AEG_TOTAL_QCONF = 10;
   localparam AEG_AVG_PROC = 11;
   localparam AEG_AVG_MEM = 12;
   localparam AEG_AVG_HIST = 13;
   localparam AEG_MEM_HIST_CONF = 14;
   
   localparam RESCUE_TIME = 32'hFFFF_FFFF;
   
   
   // Report collection
   reg [63:0] r_total_cycles;
   wire [63:0] total_cycles;
   
   reg [63:0] r_total_events;
   wire [63:0] total_events;

   reg [63:0] r_total_stalls;
   wire [63:0] total_stalls;
   
   reg [63:0] r_total_antimsg;
   wire [63:0] total_antimsg;

   reg [63:0] r_total_qconf;
   wire [63:0] total_qconf;
   
   reg [63:0] r_mem_hist_conf;
   wire [63:0] mem_hist_conf;

   reg [63:0] r_avg_proc_time;
   wire [63:0] avg_proc_time;

   reg [63:0] r_avg_mem_time;
   wire [63:0] avg_mem_time;

   reg [63:0] r_avg_hist_time;
   wire [63:0] avg_hist_time;

   assign disp_aeg_cnt = NA;

   reg          r_gvt_returned;
   reg  [63:0]  r_gvt;
   wire [63:0]  aeg[NA-1:0];

   wire xbar_enabled = MC_XBAR;

   // Setting up data to AEG
   genvar g;
   generate for (g=0; g<NA; g=g+1) begin : g0
      reg [63:0] c_aeg, r_aeg;

      always @* begin
         c_aeg = r_aeg;
         if (disp_aeg_wr && disp_aeg_idx[NB-1:0] == g)
            c_aeg = disp_aeg_wr_data;
         else begin
            case(g)
            AEG_GVT :
               if (r_gvt_returned)
                  c_aeg = r_gvt;
            AEG_TOTAL_CYCLES:
               c_aeg = r_total_cycles;
            AEG_TOTAL_EVENTS :
               c_aeg = r_total_events;
            AEG_TOTAL_STALLS :
               c_aeg = r_total_stalls;
            AEG_TOTAL_ANTIMSG :
               c_aeg = r_total_antimsg;
            AEG_TOTAL_QCONF :
               c_aeg = r_total_qconf;
            AEG_MEM_HIST_CONF :
               c_aeg = r_mem_hist_conf;
            AEG_AVG_PROC :
               c_aeg = r_avg_proc_time;
            AEG_AVG_MEM :
               c_aeg = r_avg_mem_time;
            AEG_AVG_HIST :
               c_aeg = r_avg_hist_time;
            endcase
         end 
      end

    always @(posedge clk) begin
      r_aeg <= c_aeg;
    end
    assign aeg[g] = r_aeg;
   end endgenerate

   // Handle calls to correct AEG

   reg      r_rtn_vld, r_err_unimpl, r_err_aegidx;
   reg [63:0]   r_rtn_data;

   wire c_val_aegidx = disp_aeg_idx < NA;

   always @(posedge clk) begin
      r_rtn_vld    <= disp_aeg_rd;
      r_rtn_data   <= c_val_aegidx ? aeg[disp_aeg_idx[NB-1:0]] : 64'h0;
      r_err_aegidx <= (disp_aeg_wr || disp_aeg_rd) && !c_val_aegidx;
      r_err_unimpl <= (disp_inst_vld && disp_inst != 5'd0);
   end
   assign disp_rtn_data_vld = r_rtn_vld;
   assign disp_rtn_data     = r_rtn_data;

   //assign disp_exception[1:0] = {r_err_aegidx, r_err_unimpl};

   //
   // Dispatch logic
   //

   // cae_vadd64 requires arrays to start on a 64 byte boundary to faciliate
   // using rd64 and wr64 operations
   //wire c_unaligned_addr = |{aeg[AEG_ADDR_A1][5:0], aeg[AEG_ADDR_A2][5:0], aeg[AEG_ADDR_A3][5:0]};

   wire c_caep00 = disp_inst_vld && disp_inst == 5'd0;

   //wire [NUM_MC_PORTS-1:0] r_sum_ovrflw_vec, r_res_ovrflw_vec, r_sum_vld_vec;
   reg      r_caep00, r_idle;

   always @(posedge clk) begin
      r_caep00 <= c_caep00;
      r_idle   <= disp_idle;
   end

   assign disp_exception = 0;

   // Rescue counter
   reg [31:0] rescue_timer;
   always @(posedge clk) begin
      if(i_reset) begin
         rescue_timer <= 0;
      end
      else
         rescue_timer = rescue_timer + 1;
   end

wire phold_cleanup;

   //
   // Control state machine
   //
    localparam  IDLE = 2'd0,
                RUNNING = 2'd1,
                FINISHED = 2'd2;

    wire        phold_rtn_vld;
    reg [1:0]   c_state, r_state;
    wire [15:0] phold_gvt;
    reg [15:0]  c_gvt;
    always @* begin
        c_state = r_state;
        c_gvt = r_gvt;
        case (r_state)
        IDLE: begin
            if (r_caep00) begin
                c_state = RUNNING;
                $display("simulation: Simulation state changed to RUNNING");
            end
        end
        RUNNING: begin
            if(i_aeid == 4'h0) begin
                if( (phold_rtn_vld && phold_cleanup) || rescue_timer == RESCUE_TIME) begin
                    c_state = FINISHED;
                    c_gvt = phold_gvt;
                    $display("simulation: Simulation state changed to FINISHED. GVT is %d", c_gvt);
                end
            end
            else begin
                c_state = FINISHED;
            end
        end
        FINISHED:begin
            c_state = IDLE;
        end
        default:
            c_state = IDLE;
        endcase
    end

   // ISE can have issues with global wires attached to D(flop)/I(lut) inputs
   wire r_reset;
   FDSE rst (.C(clk),.S(i_reset),.CE(r_reset),.D(!r_reset),.Q(r_reset));

    always @(posedge clk) begin
        r_state <= r_reset ? 2'b0 : c_state;
        r_gvt_returned <= (c_state == FINISHED);
        r_gvt <= r_reset ? 64'b0 : {50'b0, c_gvt};
    end
    
    // Report back
    always @(posedge clk) begin
       r_total_cycles <= r_reset ? 0 : (phold_rtn_vld ? total_cycles : r_total_cycles);
       r_total_stalls <= r_reset ? 0 : (phold_rtn_vld ? total_stalls : r_total_stalls);
       r_total_events <= r_reset ? 0 : (phold_rtn_vld ? total_events : r_total_events);
       r_total_antimsg <= r_reset ? 0 : (phold_rtn_vld ? total_antimsg : r_total_antimsg);
       r_total_qconf <= r_reset ? 0 : (phold_rtn_vld ? total_qconf : r_total_qconf);
       r_mem_hist_conf <= r_reset ? 0 : (phold_rtn_vld ? mem_hist_conf : r_mem_hist_conf);
       r_avg_mem_time <= r_reset ? 0 : (phold_rtn_vld ? avg_mem_time : r_avg_mem_time);
       r_avg_hist_time <= r_reset ? 0 : (phold_rtn_vld ? avg_hist_time : r_avg_hist_time);
       r_avg_proc_time <= r_reset ? 0 : (phold_rtn_vld ? avg_proc_time : r_avg_proc_time);
    end
    
    wire phold_rst_n = !r_reset && (r_state == RUNNING) && (i_aeid == 0);
   
   assign disp_idle  = (r_state == IDLE) && !r_caep00;
   assign disp_stall = (r_state != IDLE) || c_caep00 || r_caep00;

   //
   // CSR debug - base address is 0x8000
   //
    localparam  CAE_CSR_STATUS  = 16'd0,  // 0x8000
        CAE_CSR_GVT = 16'h1;  // 0x8001

    reg     c_csr_rd_ack, r_csr_rd_ack;
    reg  [63:0] c_csr_rd_data, r_csr_rd_data;

    always @* begin
    c_csr_rd_ack = csr_rd_vld;
    c_csr_rd_data = 64'h0;

    case(csr_address)
    CAE_CSR_STATUS: c_csr_rd_data = {61'b0, r_state};
    CAE_CSR_GVT: c_csr_rd_data = r_gvt;
    default:    c_csr_rd_data = 64'h0;
    endcase
    end
  
    always @(posedge clk) begin
      r_csr_rd_ack <= c_csr_rd_ack;
      r_csr_rd_data <= c_csr_rd_data;
    end
 
    assign csr_rd_ack = r_csr_rd_ack;
    assign csr_rd_data = r_csr_rd_data;
    
    reg [63:0] config_bits;
    reg [63:0] r_core_mask;
    always @(posedge clk) begin
       config_bits <= aeg[AEG_CONFIG];
       r_core_mask <= aeg[AEG_COREMASK];
    end
    
    wire [7:0] config_lp_mask = config_bits[7:0];
    wire [3:0] config_num_memcall = config_bits[19:16];
    wire [15:0] config_fixed_delay = config_bits[47:32];

    // Instantiate phold
// genvar i;
// generate for (i=0; i<NUM_MC_PORTS; i=i+1) begin : fp
    phold #(
        .NUM_MC_PORTS   ( NUM_MC_PORTS ),
        .MC_RTNCTL_WIDTH    ( RTNCTL_WIDTH )
    ) inst_phold (
        .clk          ( clk ),
		.sim_end      ( aeg[AEG_SIM_END_TIME][15:0] ),
        .addr         ( aeg[AEG_ADDR_A1][47:0] ),
		.num_init_events ( aeg[AEG_NUM_INIT_EVENTS][8:0] ),
		.lp_mask      ( config_lp_mask ),
      .num_memcall  ( config_num_memcall ),
      .fixed_delay  ( config_fixed_delay ),
      .core_mask    ( r_core_mask ),
      
        .gvt          ( phold_gvt ),
        .rtn_vld      ( phold_rtn_vld ),
        .cleanup      ( phold_cleanup ),
        
        .mc_rq_vld    ( mc_rq_vld ),
        .mc_rq_cmd    ( mc_rq_cmd ),
        .mc_rq_scmd   ( mc_rq_scmd ),
        .mc_rq_vadr   ( mc_rq_vadr ),
        .mc_rq_size   ( mc_rq_size ),
        .mc_rq_rtnctl ( mc_rq_rtnctl ),
        .mc_rq_data   ( mc_rq_data ),
        .mc_rq_flush  ( mc_rq_flush ),
        .mc_rq_stall  ( mc_rq_stall ),
        .mc_rs_vld    ( mc_rs_vld ),
        .mc_rs_cmd    ( mc_rs_cmd ),
        .mc_rs_scmd   ( mc_rs_scmd ),
        .mc_rs_rtnctl ( mc_rs_rtnctl ),
        .mc_rs_data   ( mc_rs_data ),
        .mc_rs_stall  ( mc_rs_stall ),
        
        .total_cycles ( total_cycles ),
        .total_stalls ( total_stalls ),
        .total_events ( total_events ),
        .total_antimsg ( total_antimsg ),
        .total_q_conf (total_qconf ),
        .mem_hist_conf(mem_hist_conf),
        .avg_mem_time (avg_mem_time ),
        .avg_hist_time (avg_hist_time ),
        .avg_proc_time (avg_proc_time),
        
        .rst_n        ( phold_rst_n )
    );
// end endgenerate

   /* ---------- debug & synopsys off blocks  ---------- */

   // synopsys translate_off

   // Parameters: 1-Severity: Don't Stop, 2-start check only after negedge of reset
   //assert_never #(1, 2, "***ERROR ASSERT: unimplemented instruction cracked") a0 (.clk(clk), .reset_n(!i_reset), .test_expr(r_unimplemented_inst));

   // Parameters: 0-Severity: Stop, 2-start check only after negedge of reset
   // assert_never #(0, 2, "***ERROR ASSERT: Number of MC Ports must be a power of 2") a1 (.clk(clk), .reset_n(!i_reset), .test_expr(|config_err));

    // synopsys translate_on

endmodule // cae_pers
