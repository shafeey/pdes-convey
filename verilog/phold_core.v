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
   input [31:0] cur_event_msg,
	
	input [`TW-1:0] global_time,
	
	// Receive a random number
	input [NRB-1:0] random_in,
	
	// New generated event
	output reg new_event_ready,
   output [31:0] out_event_msg,
   
	output active,
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
   
   reg [`TW-1:0] new_event_time;
	reg [NIDB-1:0] new_event_target;
   
	reg [NIDB-1:0] cur_lp_id;
	reg [`TW-1:0] cur_event_time;
   reg cur_event_type;
   
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
	reg [`TW-1:0] gvt;
   
   // MC interface
	assign mc_rq_vld = r_rq_vld;
	assign mc_rq_cmd = r_rq_cmd;
	assign mc_rq_rtnctl ={ {(32-NCB-1){1'b0}},r_hold, core_id}; // NOTE: verify number of preceding zeros when making adjustment
	assign mc_rq_data = {r_hold, 13'b0, core_id, 13'b0, cur_lp_id, 16'b0, cur_event_time};
	assign mc_rq_vadr = r_rq_vadr;
	assign mc_rq_scmd = 4'h0;
	assign mc_rq_size = MC_SIZE_QUAD;	// all requests are 8-byte
	assign mc_rq_flush = 1'b0;		// write flush not used in this design

	assign mc_rs_stall = 1'b0;		// we can always take responses since we
					// have room in the result fifo for any 
					// data we've requested
	
	always@(posedge clk) begin
		if(event_valid) begin
         cur_lp_id <= cur_event_msg[`TW +: NIDB];
         cur_event_time <= cur_event_msg[0 +: `TW];
         cur_event_type <= cur_event_msg[`TW + NIDB];
			gvt <= global_time;
			rnd <= random_in;
		end
   end

   // States
	localparam IDLE = 4'd0;
	localparam STALL = 4'd1;
   localparam READ_HIST = 4'd2;
   localparam LD_MEM = 4'd3;
	localparam LD_RTN = 4'd4;
   localparam PROC_EVT = 4'd5;
	localparam WRITE_HIST = 4'd6;
	localparam ST_MEM = 4'd7;
	localparam ST_RTN = 4'd8;
	localparam WAIT = 4'd9;
            
   localparam CANCELLATION_EVT = 1;
   localparam REGULAR_EVT = 0;
            
   wire [31:0] new_event_msg = {12'b0, 1'b0, new_event_target, new_event_time};
				
	reg [3:0] c_state, r_state;
	reg c_event_ready, r_event_ready;
	wire finished, read_hist_finished;
	wire ld_rtn_vld, st_rtn_vld;
	wire ld_rtn_vld2, st_rtn_vld2;
   
   assign active = (r_state != IDLE) && rst_n;
   
   reg [7:0] c_hist_addr;
   reg [31:0] c_hist_data_wr;
   
   wire [31:0] out_buf_dout, out_buf_din;
   reg [31:0] cancel_evt_msg;
   reg c_gen_cancel, r_gen_cancel;
   reg c_discard_hist_entry, c_discard_cur_evt, r_discard_cur_evt;
   wire hist_buf_rd_en, hist_buf_wr_en;
   wire [31:0] hist_buf_data;
   wire hist_buf_full, hist_buf_empty;
   wire [3:0] hist_buf_cnt;
   
   reg [3:0] hist_buf_ret_size;
   
   reg [3:0] c_hist_cnt, r_hist_cnt;
   reg c_hist_rq, r_hist_rq;
   reg c_hist_wr, r_hist_wr;
   reg c_hist_filt_done, r_hist_filt_done;
   reg c_gen_next_evt;
   
	reg [31:0] c_out_event_msg;
   reg[31:0] r_out_event_msg;
	reg c_rollback_msg_type, r_rollback_msg_type;
   reg c_out_buf_rd_en;
   wire [31:0] rollback_cncl_msg, rollback_evt_msg, null_msg;
   wire out_buf_empty;
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
      
      c_hist_filt_done = 0;
      c_rollback_msg_type = 0;
      c_gen_next_evt = 0;
      
      c_out_event_msg = r_out_event_msg;
      
		case(r_state)
		IDLE : begin
			if(event_valid) begin
				c_state = stall ? STALL : READ_HIST;
			end
      end
      STALL : begin
         if(!stall)
            c_state = READ_HIST;
      end
      
		READ_HIST: begin
         if(hist_size == 0) begin
            c_state = LD_MEM;
         end 
         else begin
   			c_hist_rq = 1'b1;
            c_hist_addr = cur_lp_id * 16 + r_hist_cnt;
            c_hist_cnt = r_hist_cnt;
            if(hist_access_grant) begin
               c_hist_cnt = r_hist_cnt + 1;
               if(r_hist_cnt == hist_size - 1 ) begin
                  c_hist_cnt = 0;
                  c_hist_rq = 0;
         			c_state = LD_MEM;
                  c_hist_filt_done = 1;
               end
            end
         end
      end
      
		LD_MEM: begin
			if(~r_mc_rq_stall) begin
            c_rq_vadr = addr + cur_lp_id * NUM_MEM_BYTE;
				c_rq_vld = 1'b1;
				c_rq_cmd = AEMC_CMD_RD8;
			end
			if(mem_gnt) begin
            c_rq_vadr = addr + cur_lp_id * NUM_MEM_BYTE + 8;
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
            c_state = PROC_EVT;
            c_rtn1 = 0;
            c_rtn2 = 0;
         end
      end
      
      PROC_EVT: begin
         c_state = WRITE_HIST;
         c_gen_next_evt = 1;
         if(r_discard_cur_evt)
            c_gen_next_evt = 0;
      end

 		WRITE_HIST: begin
         if(hist_buf_empty) begin
            c_hist_cnt = 0;
            c_hist_wr = 0;
            c_hist_rq = 0;
            c_state = ST_MEM;
         end 
         else begin
            c_hist_rq = 1;
            c_hist_wr = 1;
            c_hist_addr = cur_lp_id * 16 + r_hist_cnt;
            c_hist_data_wr = hist_buf_data;
            c_hist_cnt = r_hist_cnt;
            if(hist_access_grant) begin
               c_hist_cnt = r_hist_cnt + 1;
               if(r_hist_cnt == hist_buf_ret_size -1) begin 
                  c_hist_cnt = 0;
                  c_hist_wr = 0;
                  c_hist_rq = 0;
                  c_state = ST_MEM;
               end 
            end
         end
		end
      
		ST_MEM: begin
			if(~r_mc_rq_stall) begin
            c_rq_vadr = addr + cur_lp_id * NUM_MEM_BYTE;
				c_rq_vld = 1'b1;
				c_rq_cmd = AEMC_CMD_WR8;
			end
			if(mem_gnt) begin
            c_rq_vadr = addr + cur_lp_id * NUM_MEM_BYTE + 8;
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
            if(r_discard_cur_evt) begin
               if(r_gen_cancel) begin
                  c_out_event_msg = cancel_evt_msg;
               end
               else
                  c_out_event_msg = null_msg;
            end
            else begin
               if(cur_event_type == CANCELLATION_EVT && hist_size == 0)
                  c_out_event_msg = null_msg;
               else
                  c_out_event_msg = new_event_msg;
            end 
			end
		end
		WAIT: begin // Wait for the generated event to be received
         c_event_ready = r_event_ready;
         c_out_event_msg = r_out_event_msg;
         c_rollback_msg_type = r_rollback_msg_type;
         if(ack) begin
            if(out_buf_empty) begin // No rollback events to push to queue
               c_event_ready = 0;
               c_state = IDLE;
            end 
            else begin // Has rollback events to push
               // current event is a regular event
               // Need a rollback event and a cancellation message
                  if(r_rollback_msg_type == 0) begin
                     c_rollback_msg_type = 1;
                     c_out_event_msg = rollback_cncl_msg;
                  end
                  else begin
                     c_rollback_msg_type = 0;
                     c_out_event_msg = rollback_evt_msg;
                     c_out_buf_rd_en = 1;
                  end 
            end
         end
      end 
		endcase
   end
   
   always @(posedge clk) begin
      if(~rst_n || r_state == IDLE) begin
         r_event_ready <= 0;
         r_out_event_msg <= 0;
         r_rollback_msg_type <= 0;
      end 
      else begin 
         r_event_ready <= c_event_ready; 
         r_out_event_msg <= c_out_event_msg;
         r_rollback_msg_type <= c_rollback_msg_type;
      end 
   end
   
   assign out_event_msg = r_out_event_msg | {hist_buf_ret_size, 28'b0};
   
   wire [`TW-1:0] rollback_entry_time;
   wire [NIDB-1:0] rollback_entry_target, rollback_entry_lp;
   wire [7:0] rollback_entry_offset;
   
   assign rollback_entry_time = out_buf_dout[0 +: `TW];
   assign rollback_entry_lp = out_buf_dout[`TW +: NIDB];
   assign rollback_entry_target = out_buf_dout[30:28];
   assign rollback_entry_offset = out_buf_dout[27:20];
   
   assign null_msg = {12'b0, 1'b1, {NIDB{1'b0}}, `TW'b0};
   assign rollback_evt_msg = {12'b0, 1'b0, rollback_entry_lp, rollback_entry_time};
   assign rollback_cncl_msg = {12'b0, 1'b1, rollback_entry_target, (rollback_entry_time + rollback_entry_offset)}; 
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
      r_hist_filt_done <= c_hist_filt_done;
      hist_buf_ret_size <= (~rst_n || r_state == IDLE) ? 0 : 
                              (c_gen_next_evt ? hist_buf_ret_size + 1 : 
                                 (r_hist_filt_done ? hist_buf_cnt : hist_buf_ret_size));
      
    end
	
	reg [2:0] counter;
	always@(posedge clk) begin
		r_state <= (rst_n) ? c_state : 1'b0;
		counter <= (rst_n) ? 
						(r_state == WRITE_HIST ? counter + 1 : 3'b0) : 3'b0; 
		
		new_event_ready <= rst_n ? c_event_ready : 0;
		new_event_time <= cur_event_time + 10 + rnd [4:0]; // Keep at least 10 units time gap between events
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
      
//      if(r_state == WRITE_HIST && hist_rq) $display("Writing: core %h, address %h, data %h", core_id, hist_addr, hist_data_wr);
//      if(r_state == READ_HIST && hist_rq) $display("Reading: core %h, address %h, data %h", core_id, hist_addr, hist_data_rd);
      
   end
   assign hist_data_wr = c_hist_data_wr;
      assign hist_addr = c_hist_addr;
   assign hist_wr_en = r_hist_wr;
   assign hist_rq = r_hist_rq;
   
   wire [`TW-1:0] new_event_time_offest;
   wire [31:0] hist_buf_din;
   
   assign new_event_time_offest = new_event_time - cur_event_time;
   
   assign hist_buf_wr_en = (~hist_wr_en && hist_rq && hist_access_grant && ~c_discard_hist_entry) ||
                              c_gen_next_evt;
   assign hist_buf_din = c_gen_next_evt ? 
                                 {new_event_target , new_event_time_offest[7:0] ,cur_event_type, cur_lp_id, cur_event_time}
                                 : hist_data_rd;
   assign hist_buf_rd_en = r_hist_wr;
   
   fwft_fifo #(
      .width(32),
      .DEPTH(16)
   ) hist_buffer (
      .rst       (~rst_n || r_state == IDLE ),
      .clk       (clk                ),
      .rd_en     (hist_buf_rd_en     ),
      .dout      (hist_buf_data      ),
      .empty     (hist_buf_empty     ),
      .full      (hist_buf_full      ),
      .data_count(hist_buf_cnt       ),
      .wr_en     (hist_buf_wr_en     ),
      .din       (hist_buf_din       )
   );
	
   /*
    * Event history filter
    */
   wire [`TW-1:0] hist_time; 
   assign hist_time = hist_data_rd[0 +: `TW];
   wire hist_type;
   assign hist_type = hist_data_rd[`TW + NIDB]; // 1 = Cancellation Event, 0 = regular event
   wire [NIDB-1:0] hist_target;
   assign hist_target = hist_data_rd[`TW +: NIDB];
   reg c_cancel_match_found, r_cancel_match_found;
   reg c_gen_rollback;
   
   always @* begin 
      c_discard_hist_entry = 0;
      c_cancel_match_found = r_cancel_match_found;
      c_discard_cur_evt = r_discard_cur_evt;
      c_gen_rollback = 0;
      c_gen_cancel = r_gen_cancel;
      if(r_state == READ_HIST && hist_size != 0) begin
         if(hist_time < gvt) begin // History entry is expired, no chance of rollback
            c_discard_hist_entry = 1;
         end 
         else if(hist_type != cur_event_type  && hist_time == cur_event_time && !r_cancel_match_found) begin
            /* Event in stack and the current event are cancellation for each other */
            /* Don't put back the entry to history again.
             * Set a flag to indicate the match is found, to prevent cancellation twice.
             * The current event will not go into history after being processed.
             */
            c_discard_hist_entry = 1;
            c_cancel_match_found = 1;
            c_discard_cur_evt = 1;
            if(cur_event_type == CANCELLATION_EVT) begin 
               /* This event has already made changes that need to be rolled back */
               c_gen_cancel = 1;
            end 
         end 
         else if(cur_event_type == REGULAR_EVT && hist_type == REGULAR_EVT && hist_time > cur_event_time) begin
            /* Current event is a regular event, and has earlier timestamp than an already
             * processed regular event in the history, so the history entry has to be rolled back
             */
             
            c_discard_hist_entry = 1;
            c_gen_rollback = 1;
         end
      end 
   end 
   
   always @(posedge  clk) begin 
      r_cancel_match_found <= (r_state == IDLE) ? 0 : c_cancel_match_found;
      r_discard_cur_evt <= (r_state == IDLE) ? 0 : c_discard_cur_evt;
      cancel_evt_msg <= (r_state == IDLE) ? 0 :
                              (c_gen_cancel ? 
                                 { 12'b0, 1'b1, hist_target, hist_time } : cancel_evt_msg);
      r_gen_cancel <= (r_state == IDLE) ? 0 : c_gen_cancel;
   end 
   
   //TODO: parameterize offset
   wire out_buf_wr_en;
   assign out_buf_wr_en = c_gen_rollback;
   assign out_buf_din = hist_data_rd;
                           
   fwft_fifo #(
      .width(32),
      .DEPTH(16)
   ) out_buffer (
      .rst       (~rst_n || r_state == IDLE ),
      .clk       (clk               ),
      .rd_en     (c_out_buf_rd_en     ),
      .dout      (out_buf_dout      ),
      .empty     (out_buf_empty     ),
      .full      (),
      .data_count(),
      .wr_en     (out_buf_wr_en     ),
      .din       (out_buf_din       )
   );
   
   
    
endmodule