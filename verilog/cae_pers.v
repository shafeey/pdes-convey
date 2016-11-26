/*****************************************************************************/
//
// Module	   : cae_pers.vpp
// Revision	   :  Revision: 1.16  
// Last Modified On:  Date: 2013-10-29 19:53:40  
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
//                   /opt/convey/pdk/<rev>/<platform>/doc/cae_pers.v
//
//-----------------------------------------------------------------------------
//
// Copyright (c) 2007-2013 : created by Convey Computer Corp. This model is the
// confidential and proprietary property of Convey Computer Corp.
//
/*****************************************************************************/
/*  Id: cae_pers.vpp,v 1.16 2013-10-29 19:53:40 gedwards Exp   */

`timescale 1 ns / 1 ps

`include "pdk_fpga_defines.vh"

(* keep_hierarchy = "true" *)
module cae_pers #(
   parameter    NUM_MC_PORTS = 1,
   parameter    RTNCTL_WIDTH = 32
) (
   //
   // Clocks and Resets
   //
   input		clk,		// Personalitycore clock
   input		clkhx,		// half-rate clock
   input		clk2x,		// 2x rate clock
   input		i_reset,	// global reset synchronized to clk

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
   input				csr_wr_vld,
   input				csr_rd_vld,
   input  [15:0]			csr_address,
   input  [63:0]			csr_wr_data,
   output				csr_rd_ack,
   output [63:0]			csr_rd_data,

   //
   // Miscellaneous
   //
   input  [3:0]		i_aeid
);

`include "pdk_fpga_param.vh"
`include "aemc_messages.vh"

/*initial begin
	$dumpfile("dump.vcd");
	$dumpvars(1, testbench.cae_fpga0.ae_top.core.cae_pers.clk, 
				testbench.cae_fpga0.ae_top.core.cae_pers.inst_phold,
				testbench.cae_fpga0.ae_top.core.cae_pers.inst_phold.gen_phold_core[1].phold_core_inst);
	$dumpoff;
	#200;
	$dumpon;
	#50;
	$dumpoff;
end */
	//**************************************************************************
	//			   PERSONALITY SPECIFIC LOGIC
	//**************************************************************************

	//
	// AEG[0..NA-1] Registers
	//

	localparam NA = 8;
	localparam NB = 3;
	localparam AEG_ADDR_A1 = 0;	// Array 1 address
	localparam AEG_GVT = 1; // GVT return on AEG[1]

	assign disp_aeg_cnt = NA; // Number of AEG registers implemented in the CAE

	reg			r_gvt_returned;
	reg	[63:0]	r_gvt;
	wire	[63:0]	aeg[NA-1:0];

	wire xbar_enabled = MC_XBAR;

	//
	//	Setting data to aeg
	//
   genvar g;
   generate for (g=0; g<NA; g=g+1) begin : g0
      reg [63:0] c_aeg, r_aeg;

      always @* begin
	 c_aeg = r_aeg;
         if (disp_aeg_wr && disp_aeg_idx[NB-1:0] == g)
            c_aeg = disp_aeg_wr_data;
         else if (g==AEG_GVT && r_gvt_returned)
            c_aeg = r_gvt;
      end

      always @(posedge clk) begin
	r_aeg <= c_aeg;
      end
      assign aeg[g] = r_aeg;
   end endgenerate

	// 
	// Handle calls to correct AEG
	//
	reg			r_rtn_vld, r_err_unimpl, r_err_aegidx;
	reg [63:0]	r_rtn_data;

	wire c_val_aegidx = disp_aeg_idx < NA; 

	always @(posedge clk) begin
		r_rtn_vld    <= disp_aeg_rd;
		r_rtn_data   <= c_val_aegidx ? aeg[disp_aeg_idx[NB-1:0]] : 64'h0;
		r_err_aegidx <= (disp_aeg_wr || disp_aeg_rd) && !c_val_aegidx;
		r_err_unimpl <= (disp_inst_vld && disp_inst != 5'd0);
	end
	assign disp_rtn_data_vld = r_rtn_vld;
	assign disp_rtn_data     = r_rtn_data;

	assign disp_exception[1:0] = {r_err_aegidx, r_err_unimpl};


	//
	// Dispatch logic
	//
	wire c_caep00 = disp_inst_vld && disp_inst == 5'd0;

	reg		r_caep00, r_idle;
   
	always @(posedge clk) begin
		r_caep00 <= c_caep00;
		r_idle <= disp_idle;
	end

	//
	// Control state machine
	//
	localparam 	IDLE = 2'd0,
				RUNNING = 2'd1,
				FINISHED = 2'd2;

	wire 		phold_rtn_vld;
	reg	[1:0]	c_state, r_state;
	wire [15:0] phold_gvt;
	reg [15:0] 	c_gvt;
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
			if(phold_rtn_vld) begin
				c_state = FINISHED;
				c_gvt = phold_gvt;
				$display("simulation: Simulation state changed to FINISHED. GVT is %d", c_gvt);
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
	
	wire phold_rst_n = !r_reset && (r_state == RUNNING);
   
	assign disp_idle  = (r_state == IDLE) && !r_caep00;
	assign disp_stall = (r_state != IDLE) || c_caep00 || r_caep00;

   //
   // CSR debug - base address is 0x8000
   //
   
    localparam	CAE_CSR_STATUS	= 16'd0,  // 0x8000
		CAE_CSR_GVT	= 16'h1;  // 0x8001

    reg		c_csr_rd_ack, r_csr_rd_ack;
    reg  [63:0]	c_csr_rd_data, r_csr_rd_data;

    always @* begin
		c_csr_rd_ack = csr_rd_vld;
		c_csr_rd_data = 64'h0;

		case(csr_address)
			CAE_CSR_STATUS:
				c_csr_rd_data = {62'b0, r_state};
			CAE_CSR_GVT:
				c_csr_rd_data = r_gvt;
			default:
				c_csr_rd_data = 64'h0;
		endcase
    end
  
    always @(posedge clk) begin
      r_csr_rd_ack <= c_csr_rd_ack;
      r_csr_rd_data <= c_csr_rd_data;
    end
 
    assign csr_rd_ack = r_csr_rd_ack;
    assign csr_rd_data = r_csr_rd_data;
	
	// Instantiate phold
// genvar i;
// generate for (i=0; i<NUM_MC_PORTS; i=i+1) begin : fp
	phold #(
		.NUM_MC_PORTS   ( NUM_MC_PORTS ),
		.MC_RTNCTL_WIDTH	( RTNCTL_WIDTH )
	) inst_phold (
		.clk          ( clk ),
		.rst_n        ( phold_rst_n ),
		.addr         ( aeg[AEG_ADDR_A1][47:0] ),
		.gvt          ( phold_gvt ),
		.rtn_vld      ( phold_rtn_vld ),
		
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
		.mc_rs_stall  ( mc_rs_stall )
	);
// end endgenerate

   /* ---------- debug & synopsys off blocks  ---------- */

   // synopsys translate_off

   // Parameters: 1-Severity: Don't Stop, 2-start check only after negedge of reset
   //assert_never #(1, 2, "***ERROR ASSERT: unimplemented instruction cracked") a0 (.clk(clk), .reset_n(!i_reset), .test_expr(r_unimplemented_inst));

    // synopsys translate_on

endmodule // cae_pers
