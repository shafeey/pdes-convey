`include "global_params.vh"

module phold_core
	#(
	parameter NIDB = 3, // Number of bits in ID. Number of Available LP < 2 ^ NIDB
	parameter NRB = 8,	// Number of bits in Random number generator
	parameter NCB = 2,	//  Number of bits in core id;
	parameter    MC_RTNCTL_WIDTH = 32
	)(
	input clk,
	input rst_n,
	input [NCB-1:0] core_id,
	
	// Incoming events
	input event_valid,
	input [NIDB-1:0] event_id,
	input [`TW-1:0] event_time,
	
	input [`TW-1:0] global_time,
	
	// Receive a random number
	input [NRB-1:0] random_in,
	
	// New generated event
	output reg [`TW-1:0] new_event_time,
	output reg [NIDB-1:0] new_event_target,
	output reg new_event_ready,
	
	output ready,
	input ack,
	
	// Memory interface
	output		mc_rq_vld,
   output [2:0]		mc_rq_cmd,
   output [3:0]		mc_rq_scmd,
   output [47:0]	mc_rq_vadr,
   output [1:0]		mc_rq_size,
   output [MC_RTNCTL_WIDTH-1:0]	mc_rq_rtnctl,
   output [63:0]	mc_rq_data,
   output		mc_rq_flush,
   input		mc_rq_stall,

   input		mc_rs_vld,
   input  [2:0]		mc_rs_cmd,
   input  [3:0]		mc_rs_scmd,
   input  [MC_RTNCTL_WIDTH-1:0]	mc_rs_rtnctl,
   input  [63:0]	mc_rs_data,
   output		mc_rs_stall,
   
   input [47:0] addr,
   input 		mem_gnt
);
	`include "aemc_messages.vh"

   reg          c_rq_vld;
   reg          r_rq_vld;
   reg  [2:0]   c_rq_cmd;
   reg  [2:0]   r_rq_cmd;
   reg  [47:0]  c_rq_vadr;
   reg  [47:0]  r_rq_vadr;
   reg  [31:0]  c_rq_rtnctl;
   reg  [31:0]  r_rq_rtnctl;
   reg  [63:0]  c_rq_data;
   reg  [63:0]  r_rq_data;
   reg          r_rs_vld;
   reg  [2:0]   r_rs_cmd;
   reg  [31:0]  r_rs_rtnctl;
   reg  [63:0]  r_rs_data;

   reg          r_mc_rq_stall;
   
   	reg [NRB-1:0] rnd;
	reg [`TW-1:0] local_time, gvt;
	reg [NIDB-1:0] local_id;
   
   // MC interface
	assign mc_rq_vld = r_rq_vld;
	assign mc_rq_cmd = r_rq_cmd;
	assign mc_rq_rtnctl ={ {(32-NCB){1'b0}}, core_id};
	assign mc_rq_data = {14'b0, core_id, 13'b0, event_id, 16'b0, event_time};
	assign mc_rq_vadr = addr + event_id * 8;
	assign mc_rq_scmd = 4'h0;
	assign mc_rq_size = MC_SIZE_QUAD;	// all requests are 8-byte
	assign mc_rq_flush = 1'b0;		// write flush not used in this design

	assign mc_rs_stall = 1'b0;		// we can always take responses since we
					// have room in the result fifo for any 
					// data we've requested
	
	always@(posedge clk) begin
		if(event_valid) begin
			local_time <= event_time;
			local_id <= event_id;
			gvt <= global_time;
			rnd <= random_in;
		end
	end

	localparam 	IDLE = 3'd0,
				LD_MEM = 3'd1,
				LD_RTN = 3'd2,
				RND_DLY = 3'd3,
				ST_MEM = 3'd4,
				ST_RTN = 3'd5,
				WAIT = 3'd6;
				
	reg [2:0] c_state, r_state;
	reg c_event_ready;
	wire finished;
	wire ld_rtn_vld, st_rtn_vld;
	
	always@* begin
		c_state = r_state;
		c_event_ready = new_event_ready;
		c_rq_vld = 1'b0;
		c_rq_cmd = AEMC_CMD_IDLE;
		
		case(r_state)
		IDLE : begin
			if(event_valid) begin
				c_state = LD_MEM;
			end
		end
		LD_MEM: begin
			if(~r_mc_rq_stall) begin
				c_rq_vld = 1'b1;
				c_rq_cmd = AEMC_CMD_RD8;
			end
			if(mem_gnt) begin
				c_state = LD_RTN;
				c_rq_vld = 1'b0;
			end
		end
		LD_RTN: begin
			if(ld_rtn_vld) c_state = RND_DLY;
		end
		RND_DLY: begin
			if (finished) c_state = ST_MEM;	
		end
		ST_MEM: begin
			if(~r_mc_rq_stall) begin
				c_rq_vld = 1'b1;
				c_rq_cmd = AEMC_CMD_WR8;
			end
			if(mem_gnt) begin
				c_state = ST_RTN;
				c_rq_vld = 0;
			end
		end
		ST_RTN: begin
			if(st_rtn_vld) begin
				c_state = WAIT;
				c_event_ready = 1;
			end
		end
		WAIT: begin // Wait for the generated event to be received
			if (ack) begin
				c_state = IDLE;
				c_event_ready = 0;
			end
		end
		endcase
	end
	
	assign ready = (r_state == IDLE);
	assign ld_rtn_vld = r_rs_vld && (r_rs_cmd == MCAE_CMD_RD8_DATA) &&
							(r_rs_rtnctl[NCB-1:0] == core_id);
	assign st_rtn_vld = r_rs_vld && (r_rs_cmd == MCAE_CMD_WR_CMP) &&
							(r_rs_rtnctl[NCB-1:0] == core_id);
							
	
							
	always @(posedge clk) begin
      r_rs_vld  <= (~rst_n) ? 1'b0 : mc_rs_vld;
      r_rs_cmd  <= (~rst_n) ? 'd0 : mc_rs_cmd;
      r_rs_rtnctl <= (~rst_n) ? 'd0 : mc_rs_rtnctl;
      r_rs_data  <= (~rst_n) ? 'd0 : mc_rs_data;
      r_mc_rq_stall <= mc_rq_stall;
    end
	
	reg [2:0] counter;
	always@(posedge clk or negedge rst_n) begin
		r_state <= (rst_n) ? c_state : 1'b0;
		counter <= (rst_n) ? 
						(r_state == RND_DLY ? counter + 1 : 3'b0) : 3'b0; 
		
		new_event_ready <= rst_n ? c_event_ready : 0;
		new_event_time <= local_time + 10 + rnd [4:0]; // Keep at least 10 units time gap between events
		new_event_target <= rnd[NRB-1:5];
		r_rq_vld <= rst_n ? c_rq_vld : 0;
		r_rq_cmd <= c_rq_cmd;
	end
	
	assign finished = (counter == rnd[2:0]); // Simulate a random processing delay
	
endmodule