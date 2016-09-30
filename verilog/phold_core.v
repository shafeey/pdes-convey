`include "global_params.vh"

module phold_core
	#(
	parameter NIDB = 3, // Number of bits in ID. Number of Available LP < 2 ^ NIDB
	parameter NRB = 8,	// Number of bits in Random number generator
	parameter NCB = 2,	//  Number of bits in core id;
   parameter NUM_MEM_BYTE = 16,
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
	
   input stall,
	output ready,
	input ack,
   
   // Event History Interface
   output            hist_rq,
   output            hist_wr_en,
   output [7:0]    hist_addr,
   output [31:0]   hist_data_wr,
   input       [31:0]   hist_data_rd,
   input                hist_access_grant,
   input [3:0]       hist_size,
	
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
   reg          r_hold;
   reg          c_hold;
   reg          r_rtn1;
   reg          r_rtn2;
   reg          c_rtn1;
   reg          c_rtn2;
   reg [NUM_MEM_BYTE*8-1:0] rtn_data;

   reg          r_mc_rq_stall;
   
   	reg [NRB-1:0] rnd;
	reg [`TW-1:0] local_time, gvt;
	reg [NIDB-1:0] local_id;
   
   // MC interface
	assign mc_rq_vld = r_rq_vld;
	assign mc_rq_cmd = r_rq_cmd;
	assign mc_rq_rtnctl ={ {(32-NCB-1){1'b0}},r_hold, core_id}; // NOTE: verify number of preceding zeros when making adjustment
	assign mc_rq_data = {r_hold, 13'b0, core_id, 13'b0, local_id, 16'b0, event_time};
	assign mc_rq_vadr = r_rq_vadr;
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

   // States
	localparam IDLE = 3'd0;
   localparam LD_MEM = 3'd1;
	localparam LD_RTN = 3'd2;
   localparam READ_HIST = 4'd8;
	localparam WRITE_HIST = 3'd3;
	localparam ST_MEM = 3'd4;
	localparam ST_RTN = 3'd5;
	localparam WAIT = 3'd6;
	localparam STALL = 3'd7;
            
				
	reg [3:0] c_state, r_state;
	reg c_event_ready;
	wire finished, read_hist_finished;
	wire ld_rtn_vld, st_rtn_vld;
	wire ld_rtn_vld2, st_rtn_vld2;
   
   reg [7:0] c_hist_addr, r_hist_addr;
   reg [31:0] c_hist_data_wr, d_hist_wr;
   
   reg hist_buf_rd, hist_buf_wr;
   wire [31:0] hist_buf_data;
   wire hist_buf_full, hist_buf_empty;
   wire [4:0] hist_buf_count;
   
   reg [3:0] c_hist_cnt, r_hist_cnt;
   reg c_hist_rq, r_hist_rq;
   reg c_hist_wr, r_hist_wr;
   
	always@* begin
		c_state = r_state;
		c_event_ready = new_event_ready;
		c_rq_vld = 1'b0;
		c_rq_cmd = AEMC_CMD_IDLE;
      c_hold = 0;
      c_rtn1 = r_rtn1;
      c_rtn2 = r_rtn2;
      
      c_hist_cnt = 0;
		c_hist_rq = 0;
      c_hist_wr = 0;
      
		case(r_state)
		IDLE : begin
			if(event_valid) begin
				c_state = stall ? STALL : LD_MEM;
			end
      end
      STALL : begin
         if(!stall)
            c_state = LD_MEM;
      end
		LD_MEM: begin
			if(~r_mc_rq_stall) begin
            c_rq_vadr = addr + local_id * NUM_MEM_BYTE;
				c_rq_vld = 1'b1;
				c_rq_cmd = AEMC_CMD_RD8;
			end
			if(mem_gnt) begin
            c_rq_vadr = addr + local_id * NUM_MEM_BYTE + 8;
            c_hold = 1;
            if(r_hold) begin
               c_state = LD_RTN;
               c_rq_vld = 1'b0;
            end 
			end
		end
		LD_RTN: begin
			if(ld_rtn_vld) c_rtn1 = 1;
         if(ld_rtn_vld2) c_rtn2 = 1;
         
         if(r_rtn1 && r_rtn2) begin
            c_state = READ_HIST;
            c_rtn1 = 0;
            c_rtn2 = 0;
         end
		end

		READ_HIST: begin
         if(hist_size == 0) begin
            c_state = WRITE_HIST;
         end 
         else begin
   			c_hist_rq = 1'b1;
            c_hist_addr = local_id * 16 + r_hist_cnt;
            c_hist_cnt = r_hist_cnt;
            if(hist_access_grant) begin
               c_hist_cnt = r_hist_cnt + 1;
               if(r_hist_cnt == hist_size - 1 ) begin
                  c_hist_cnt = 0;
                  c_hist_rq = 0;
         			c_state = WRITE_HIST;
               end
            end
         end
      end
      
 		WRITE_HIST: begin
         c_hist_rq = 1'b1;
         c_hist_wr = 1'b1;
         c_hist_addr = local_id * 16 + r_hist_cnt;
         c_hist_data_wr = {core_id, 1'b0, local_id, r_hist_cnt};
         c_hist_cnt = r_hist_cnt;
         if(hist_access_grant) begin
            c_hist_cnt = r_hist_cnt + 1;
            if(r_hist_cnt == 3 ) begin
               c_hist_cnt = 0;
               c_hist_wr = 0;
               c_hist_rq = 0;
      			c_state = ST_MEM;
            end
         end
		end     
      
		ST_MEM: begin
			if(~r_mc_rq_stall) begin
            c_rq_vadr = addr + local_id * NUM_MEM_BYTE;
				c_rq_vld = 1'b1;
				c_rq_cmd = AEMC_CMD_WR8;
			end
			if(mem_gnt) begin
            c_rq_vadr = addr + local_id * NUM_MEM_BYTE + 8;
            c_hold = 1;
            if(r_hold) begin
   				c_state = ST_RTN;
   				c_rq_vld = 0;
            end
			end
		end
		ST_RTN: begin
         if(st_rtn_vld) c_rtn1 = 1;
         if(st_rtn_vld2) c_rtn2 = 1;
         
			if(r_rtn1 && r_rtn2) begin
            c_rtn1 = 0;
            c_rtn2 = 0;
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
							(r_rs_rtnctl[NCB:0] == { 1'b0, core_id});
	assign st_rtn_vld = r_rs_vld && (r_rs_cmd == MCAE_CMD_WR_CMP) &&
							(r_rs_rtnctl[NCB:0] == { 1'b0, core_id});
							
	assign ld_rtn_vld2 = r_rs_vld && (r_rs_cmd == MCAE_CMD_RD8_DATA) &&
							(r_rs_rtnctl[NCB:0] == { 1'b1, core_id});
	assign st_rtn_vld2 = r_rs_vld && (r_rs_cmd == MCAE_CMD_WR_CMP) &&
							(r_rs_rtnctl[NCB:0] == { 1'b1, core_id});
	
							
	always @(posedge clk) begin
      r_rs_vld  <= (~rst_n) ? 1'b0 : mc_rs_vld;
      r_rs_cmd  <= (~rst_n) ? 'd0 : mc_rs_cmd;
      r_rs_rtnctl <= (~rst_n) ? 'd0 : mc_rs_rtnctl;
      r_rs_data  <= (~rst_n) ? 'd0 : mc_rs_data;
      r_mc_rq_stall <= mc_rq_stall;
    end
	
	reg [2:0] counter;
	always@(posedge clk) begin
		r_state <= (rst_n) ? c_state : 1'b0;
		counter <= (rst_n) ? 
						(r_state == WRITE_HIST ? counter + 1 : 3'b0) : 3'b0; 
		
		new_event_ready <= rst_n ? c_event_ready : 0;
		new_event_time <= local_time + 10 + rnd [4:0]; // Keep at least 10 units time gap between events
		new_event_target <= rnd[NRB-1:5];
		r_rq_vld <= rst_n ? c_rq_vld : 0;
		r_rq_cmd <= c_rq_cmd;
      r_rq_vadr <= c_rq_vadr;
      r_hold <= rst_n ? c_hold : 0;
      r_rtn1 <= rst_n ? c_rtn1 : 0;
      r_rtn2 <= rst_n ? c_rtn2 : 0;
      rtn_data[63:0] <= rst_n ? (ld_rtn_vld ? r_rs_data : rtn_data[63:0]) : 0;
      rtn_data[127:64] <= rst_n ? (ld_rtn_vld2 ? r_rs_data : rtn_data[127:64]) : 0;
	end
	
   always @(posedge clk or negedge rst_n) begin 
      r_hist_cnt <= rst_n ? c_hist_cnt : 0;
      r_hist_rq <= rst_n ? c_hist_rq : 0;
      r_hist_wr <= rst_n ? c_hist_wr : 0;
      
      if(r_state == WRITE_HIST && local_id == 3) $display("Writing: core %h, address %h, data %h", core_id, hist_addr, hist_data_wr);
      if(r_state == READ_HIST && local_id == 3) $display("Reading: core %h, address %h, data %h", core_id, hist_addr, hist_data_rd);
      
   end
   assign hist_data_wr = c_hist_data_wr;
      assign hist_addr = c_hist_addr;
   assign hist_wr_en = r_hist_wr;
   assign hist_rq = r_hist_rq;
   
   // assign hist_addr = {core_id, r_hist_cnt};
   // assign hist_data_wr = {core_id, local_id, r_hist_cnt};
   
   always @(posedge clk or negedge rst_n) begin
      if(~rst_n) begin
         hist_buf_wr = 0;
      end 
      else begin
         if(r_state == READ_HIST && hist_rq && hist_access_grant)
               hist_buf_wr <= 1;
         else
            hist_buf_wr <= 0;
      end 
   end 

   fifo_fwft_16x32 history_fifo (
     .clk(clk), // input clk
     .rst(~rst_n), // input rst
     .din(hist_data_rd), // input [31 : 0] din
     .wr_en(hist_buf_wr), // input wr_en
     .rd_en(hist_buf_rd), // input rd_en
     .dout(hist_buf_data), // output [31 : 0] dout
     .full(hist_buf_full), // output full
     .empty(hist_buf_empty), // output empty
     .data_count(hist_buf_count) // output [4 : 0] data_count
   );
	
endmodule
