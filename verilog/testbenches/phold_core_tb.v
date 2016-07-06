`timescale 1 ns / 100 ps
`define TW 16
module phold_core_tb;

	`include "aemc_messages.vh"

// Parameter/Signal Declarations
parameter NIDB             = 3;
parameter NRB              = 8;
parameter NCB              = 2;
parameter MC_RTNCTL_WIDTH  = 32;
reg clk;
reg rst_n;
reg [NCB-1:0] core_id;
reg event_valid;
reg [NIDB-1:0] event_id;
reg [`TW-1:0] event_time;
reg [`TW-1:0] global_time;
reg [NRB-1:0] random_in;
wire [`TW-1:0] new_event_time;
wire [NIDB-1:0] new_event_target;
wire new_event_ready;
wire ready;
reg ack;
wire 	   mc_rq_vld;
wire [2:0] mc_rq_cmd;
wire [3:0] mc_rq_scmd;
wire [47:0] mc_rq_vadr;
wire [1:0] mc_rq_size;
wire [MC_RTNCTL_WIDTH-1:0] mc_rq_rtnctl;
wire [63:0] mc_rq_data;
wire mc_rq_flush;
reg  mc_rq_stall;
reg  mc_rs_vld;
reg [2:0] mc_rs_cmd;
reg [3:0] mc_rs_scmd;
reg [MC_RTNCTL_WIDTH-1:0] mc_rs_rtnctl;
reg [63:0] mc_rs_data;
wire mc_rs_stall;
reg [47:0] addr;
reg mem_gnt;

initial begin
	clk = 0;
	forever #5 clk = ~clk;
end

initial begin
	random_in = $random;
	forever @(negedge event_valid) random_in = $random;
end

initial begin
	rst_n = 1;
	event_valid = 0;
	global_time = 0;
	event_id = 5;
	event_time = 256;
	ack = 0;
	core_id = 3;
	
	mc_rq_stall = 0;
	mc_rs_vld = 0;
	mc_rs_cmd = 0;
	mc_rs_scmd = 0;
	mc_rs_rtnctl = 0;
	mc_rs_data = 0;
	
	addr = 'hf0f0;
	mem_gnt = 0;
	
	#10 rst_n = 0;
	#20 rst_n = 1;
	
	#10
	@(negedge clk)
	event_id = 2;
	event_time = 5;
	event_valid = 1;
	
	@(posedge clk)
	event_valid = 0;
	
	// memory transaction
	@(posedge mc_rq_vld)
		mem_gnt = 1;
		@(posedge clk)
		mc_rs_cmd = MCAE_CMD_RD8_DATA;
		mc_rs_rtnctl = mc_rq_rtnctl;
		mem_gnt = 0;
		mc_rs_vld = 1;
		mc_rs_data = 'hf0f0;
		@(posedge clk)
		mc_rs_vld = 0;
		
	// memory transaction
	@(posedge mc_rq_vld)
		
		@(posedge clk)
		mc_rs_cmd = MCAE_CMD_WR_CMP;
		mc_rs_rtnctl = mc_rq_rtnctl;
		mem_gnt = 1;
		@(posedge clk)
		mem_gnt = 0;
		@(posedge clk)
		mc_rs_vld = 1;
		mc_rs_data = 'hf0f0;
		@(posedge clk)
		mc_rs_vld = 0;
	
	@(posedge new_event_ready)
	@(posedge clk)
	ack = 1; // event received
	
	@(posedge clk)
	ack = 0;
	event_id = 4;
	event_time = 10;
	event_valid = 1;
	
	@(posedge clk)
	event_valid = 0;
	

	@(posedge new_event_ready)
	@(posedge clk)
	event_id = 0;
	event_time = 15;
	
	#20
	@(posedge clk)
	ack = 1;
	
	@(posedge clk)
	ack = 0;

	@(posedge clk)
	event_valid = 1;
	
	@(posedge clk)
	event_valid = 0;
	
	@(posedge new_event_ready)
	@(posedge clk)

	ack = 1; // event received
	
	@(posedge clk)
	ack = 0;
end


// Instance Declarations
phold_core
 #(
   .NIDB            ( NIDB ),
   .NRB             ( NRB ),
   .NCB             ( NCB ),
   .MC_RTNCTL_WIDTH ( MC_RTNCTL_WIDTH )
)  inst_phold_core
 (
   .clk              ( clk ),
   .rst_n            ( rst_n ),
   .core_id          ( core_id ),
   .event_valid      ( event_valid ),
   .event_id         ( event_id ),
   .event_time       ( event_time ),
   .global_time      ( global_time ),
   .random_in        ( random_in ),
   .new_event_time   ( new_event_time ),
   .new_event_target ( new_event_target ),
   .new_event_ready  ( new_event_ready ),
   .ready            ( ready ),
   .ack              ( ack ),
   .mc_rq_vld        ( mc_rq_vld ),
   .mc_rq_cmd        ( mc_rq_cmd ),
   .mc_rq_scmd       ( mc_rq_scmd ),
   .mc_rq_vadr       ( mc_rq_vadr ),
   .mc_rq_size       ( mc_rq_size ),
   .mc_rq_rtnctl     ( mc_rq_rtnctl ),
   .mc_rq_data       ( mc_rq_data ),
   .mc_rq_flush      ( mc_rq_flush ),
   .mc_rq_stall      ( mc_rq_stall ),
   .mc_rs_vld        ( mc_rs_vld ),
   .mc_rs_cmd        ( mc_rs_cmd ),
   .mc_rs_scmd       ( mc_rs_scmd ),
   .mc_rs_data       ( mc_rs_data ),
   .mc_rs_rtnctl     ( mc_rs_rtnctl ),
   .mc_rs_stall      ( mc_rs_stall ),
   .addr             ( addr ),
   .mem_gnt          ( mem_gnt )
);
endmodule