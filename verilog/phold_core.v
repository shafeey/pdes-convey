`include "global_params.vh"

module phold_core
	#(
	parameter NB_LPID = 3, // Number of bits in ID. Number of Available LP < 2 ^ NB_LP
	parameter NB_RND = 24,	// Number of bits in Random number generator
	parameter NB_COREID = 2,	//  Number of bits in core id;
   parameter NUM_MEM_BYTE = 8,
   parameter MSG_WID = 32,
   parameter TIME_WID = 16,
   parameter HIST_WID = 32,
   parameter NB_HIST_ADDR = 8,  // Bits to address the whole history memory, whole size = NUM_LP * (2**NB_HIST_DEPTH)
   parameter NB_HIST_DEPTH = 4, // Depth of history buffer reserved for each LP = 2**NB_HIST_DEPTH
	parameter    MC_RTNCTL_WIDTH = 32
	)(
	input clk,
	input rst_n,
	input [NB_COREID-1:0] core_id,
	
	// Incoming events
	input event_valid,
   input [MSG_WID-1:0] cur_event_msg,
	
	input [TIME_WID-1:0] global_time,
	
	// Receive a random number
	input [NB_RND-1:0] random_in,
   
   input [NB_LPID-1:0] lp_mask,
   input [3:0] num_memcall,
	
	// New generated event
	output reg new_event_ready,
   output [MSG_WID-1:0] out_event_msg,
   
	output active,
   input stall,
	output ready,
	input ack,
   
   // report back
   output [15:0] proc_time,
   output [15:0] mem_time,
   
   // Event History Interface
   output          hist_rq,
   output          hist_wr_en,
   output [NB_HIST_ADDR-1:0]    hist_addr,
   output [HIST_WID-1:0]   hist_data_wr,
   input       [HIST_WID-1:0]   hist_data_rd,
   input                hist_access_grant,
   input [NB_HIST_DEPTH-1:0]       hist_size,
	
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
   
   reg [TIME_WID-1:0] new_event_time;
	reg [NB_LPID-1:0] new_event_target;
   
	reg [NB_LPID-1:0] cur_lp_id;
	reg [TIME_WID-1:0] cur_event_time;
   reg cur_event_type;
   
   wire [7:0] fixed_delay = 10;
   
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
   reg          r_rtn1;
   reg          r_rtn2;
   reg          c_rtn1;
   reg          c_rtn2;
   reg [NUM_MEM_BYTE*8-1:0] rtn_data;

   reg          r_mc_rq_stall;
   
   	reg [NB_RND-1:0] rnd;
	reg [TIME_WID-1:0] gvt;
   
   localparam MEM_CNT = 1;
   
   // MC interface
	assign mc_rq_vld = r_rq_vld;
	assign mc_rq_cmd = r_rq_cmd;
	assign mc_rq_rtnctl ={{(32-NB_COREID){1'b0}}, core_id}; // NOTE: verify number of preceding zeros when making adjustment
	assign mc_rq_data = { {(16-NB_COREID){1'b0}}, core_id, {(16-NB_LPID){1'b0}}, cur_lp_id, 16'b0, cur_event_time}; // A test data pattern, of no significance
	assign mc_rq_vadr = r_rq_vadr;
	assign mc_rq_scmd = 4'h0;
	assign mc_rq_size = MC_SIZE_QUAD;	// all requests are 8-byte
	assign mc_rq_flush = 1'b0;		// write flush not used in this design

	assign mc_rs_stall = 1'b0;		// we never stall, we can always take responses since we
					// have room in the result fifo for any data we've requested
	
   reg r_event_valid;
   reg r_stall;
	always@(posedge clk) begin
      r_event_valid <= event_valid;
      r_stall <= stall;
      
		if(event_valid) begin
         cur_lp_id <= cur_event_msg[TIME_WID +: NB_LPID];
         cur_event_time <= cur_event_msg[0 +: TIME_WID];
         cur_event_type <= cur_event_msg[TIME_WID + NB_LPID];
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
   localparam PROC_DELAY = 4'd5;
   localparam GEN_EVT = 4'd6;
	localparam WRITE_HIST = 4'd7;
	localparam ST_MEM = 4'd8;
	localparam ST_RTN = 4'd9;
   localparam SEND_EVT = 4'd10;
	localparam WAIT = 4'd11;
            
   localparam EVT_TYPE_WID = 1;
   localparam CANCEL_EVT = {EVT_TYPE_WID{1'b1}};
   localparam REGULAR_EVT = {EVT_TYPE_WID{1'b0}};
            
   wire [MSG_WID-1:0] new_event_msg;
   assign new_event_msg = { {MSG_WID-NB_LPID-TIME_WID-EVT_TYPE_WID{1'b0}}, REGULAR_EVT, new_event_target, new_event_time};
				
	reg [3:0] c_state, r_state;
	reg c_event_ready, r_event_ready;
	reg finalize;
	wire finished, read_hist_finished;
	wire ld_rtn_vld, st_rtn_vld;
   wire rand_delay_reached;
   
   reg r_core_ready;
   assign active = ~r_core_ready;
   
   reg [3:0] ld_mem_counter, st_mem_counter, ld_rtn_counter;
   
   reg [NB_HIST_ADDR-1:0] c_hist_addr, r_hist_addr;
   reg [HIST_WID-1:0] c_hist_data_wr;
   reg [NB_HIST_DEPTH-1:0] r_hist_size;
   reg [HIST_WID-1:0] r_hist_data_rd, r_hist_data_wr;
   
   wire [HIST_WID-1:0] out_buf_dout, out_buf_din;
   reg [MSG_WID-1:0] cancel_evt_msg;
   reg c_gen_cancel, r_gen_cancel;
   reg c_discard_hist_entry, c_discard_cur_evt, r_discard_cur_evt;
   wire hist_buf_rd_en, hist_buf_wr_en;
   wire [HIST_WID-1:0] hist_buf_data;
   wire hist_buf_full, hist_buf_empty;
   wire [NB_HIST_DEPTH-1:0] hist_buf_cnt;
   
   reg [NB_HIST_DEPTH-1:0] hist_buf_ret_size;
   
   reg c_hist_done;
   reg [NB_HIST_DEPTH-1:0] c_hist_cnt, r_hist_cnt;
   reg c_hist_rq, r_hist_rq;
   reg c_hist_wr, r_hist_wr;
   reg c_hist_filt_done, r_hist_filt_done1, r_hist_filt_done2;
   reg c_gen_next_evt;
   
	reg [MSG_WID-1:0] c_out_event_msg;
   reg[MSG_WID-1:0] r_out_event_msg;
	reg c_rollback_msg_type, r_rollback_msg_type;
   reg c_out_buf_rd_en;
   wire [MSG_WID-1:0] rbk_cncl_msg, rbk_evt_msg, null_msg;
   wire out_buf_empty;
	always@* begin
		c_state = r_state;
		c_event_ready = new_event_ready;
		c_rq_vld = 1'b0;
		c_rq_cmd = AEMC_CMD_IDLE;
      c_rtn1 = r_rtn1;
      c_rtn2 = r_rtn2;
      
      c_rollback_msg_type = 0;
      c_gen_next_evt = 0;
      
      c_out_event_msg = r_out_event_msg;
      c_out_buf_rd_en = 0;
      
      c_rq_vadr = 0;
      finalize = 0;
      
		case(r_state)
		IDLE : begin
			if(r_event_valid) begin
				c_state = STALL;
			end
      end
      STALL : begin
         if(!r_stall)
            c_state = READ_HIST;
      end
      
		READ_HIST: begin
         if(c_hist_done)
            c_state = LD_MEM;
         
//         if(r_hist_size == 0) begin
//            c_state = PROC_DELAY;
//         end 
//         else begin
//   			c_hist_rq = 1'b1;
//            c_hist_addr = cur_lp_id * (2 ** NB_HIST_DEPTH) + r_hist_cnt;
//            c_hist_cnt = r_hist_cnt;
//            if(hist_access_grant) begin
////               $display("read history: core %d, lp:%d, cnt: %d, addr:%h, value: %h", core_id, cur_lp_id, r_hist_cnt, c_hist_addr, hist_data_rd);
//               c_hist_cnt = r_hist_cnt + 1;
//               if(r_hist_cnt == r_hist_size - 1 ) begin
//                  c_hist_cnt = 0;
//                  c_hist_rq = 0;
//         			c_state = LD_MEM;
//                  c_hist_filt_done = 1;
//               end
//            end
//         end
      end
      
		LD_MEM: begin
         if(ld_mem_counter < num_memcall) begin
   			if(~r_mc_rq_stall) begin
               c_rq_vadr = addr + cur_lp_id * NUM_MEM_BYTE;
   				c_rq_vld = 1'b1;
   				c_rq_cmd = AEMC_CMD_RD8;
   			end
   			if(mem_gnt) begin
               if(core_id == 0)
//                  $display("**Info: mem ld in 0\n");
   //            c_state = LD_RTN;
               c_rq_vld = 1'b0;
   			end
         end
         else
            c_state = LD_RTN;
      end
      
		LD_RTN: begin
			if(ld_rtn_counter == num_memcall) begin
            c_state = PROC_DELAY;
         end
      end
      
      PROC_DELAY: begin
         if(rand_delay_reached)
            c_state = GEN_EVT;
      end
            
      GEN_EVT: begin
         c_state = WRITE_HIST;
         c_gen_next_evt = 1;
         if(r_discard_cur_evt)
            c_gen_next_evt = 0;
      end

 		WRITE_HIST: begin
          if(c_hist_done)
             c_state = ST_MEM;
//         if(hist_buf_empty) begin
//            c_hist_cnt = 0;
//            c_hist_wr = 0;
//            c_hist_rq = 0;
//            c_state = SEND_EVT;
//         end 
//         else begin
//            c_hist_rq = 1;
//            c_hist_wr = 1;
//            c_hist_addr = cur_lp_id * (2 ** NB_HIST_DEPTH) + r_hist_cnt;
//            c_hist_data_wr = hist_buf_data;
//            c_hist_cnt = r_hist_cnt;
//            if(hist_access_grant) begin
////               $display("write history: core %d, lp:%d, cnt: %d, addr:%h, value: %h", core_id, cur_lp_id, r_hist_cnt, c_hist_addr, c_hist_data_wr);
//               c_hist_cnt = r_hist_cnt + 1;
//               if(r_hist_cnt == hist_buf_ret_size -1) begin 
//                  c_hist_cnt = 0;
//                  c_hist_wr = 0;
//                  c_hist_rq = 0;
//                  c_state = ST_MEM;
//               end 
//            end
//         end
		end
      
		ST_MEM: begin
         if(ld_mem_counter < num_memcall) begin
      			if(~r_mc_rq_stall) begin
                  c_rq_vadr = addr + cur_lp_id * NUM_MEM_BYTE;
      				c_rq_vld = 1'b1;
      				c_rq_cmd = AEMC_CMD_WR8;
      			end
      			if(mem_gnt) begin
      //				c_state = ST_RTN;
      				c_rq_vld = 0;
               end
         end
         else
            c_state = ST_RTN;
		end
		ST_RTN: begin
			if(ld_rtn_counter == num_memcall) begin
				c_state = SEND_EVT;
			end
      end
      
      SEND_EVT: begin
         c_event_ready = r_event_ready;
         c_out_event_msg = r_out_event_msg;
         c_rollback_msg_type = r_rollback_msg_type;
         
         if(~r_event_ready) begin
            if(out_buf_empty) begin // No rollback events to push to queue
               c_event_ready = 0;
               c_state = WAIT;
            end 
            else begin // Has rollback events to push
               c_event_ready = 1;
               // current event is a regular event
               // Need a rollback event and a cancellation message
               if(r_rollback_msg_type == 0) begin
                  c_rollback_msg_type = 1;
                  c_out_event_msg = rbk_cncl_msg;
               end
               else begin
                  c_rollback_msg_type = 0;
                  c_out_event_msg = rbk_evt_msg;
                  c_out_buf_rd_en = 1;
               end 
            end
         end
         else begin
            if(ack) begin
               c_event_ready = 0;
            end
         end
//         
//         c_event_ready = 1;
//         if(r_discard_cur_evt) begin
//            if(r_gen_cancel) begin
//               c_out_event_msg = cancel_evt_msg;
//            end
//            else
//               c_out_event_msg = null_msg;
//         end
//         else begin
//            if(cur_event_type == CANCEL_EVT)
//               c_out_event_msg = null_msg;
//            else
//               c_out_event_msg = new_event_msg;
//         end 
//         c_state = WAIT;
      end
      WAIT: begin
         c_event_ready = 1;
         finalize = 1;
         if(r_discard_cur_evt) begin
            if(r_gen_cancel) begin
               c_out_event_msg = cancel_evt_msg;
            end
            else
               c_out_event_msg = null_msg;
         end
         else begin
            if(cur_event_type == CANCEL_EVT)
               c_out_event_msg = null_msg;
            else
               c_out_event_msg = new_event_msg;
         end 
         
         if(ack) begin
            c_state = IDLE;
            c_event_ready = 0;
            finalize = 0;
         end
      end
      
//		WAIT: begin // Wait for the generated event to be received
//         c_event_ready = r_event_ready;
//         c_out_event_msg = r_out_event_msg;
//         c_rollback_msg_type = r_rollback_msg_type;
//         if(ack) begin
//            if(out_buf_empty) begin // No rollback events to push to queue
//               c_event_ready = 0;
//               c_state = IDLE;
//            end 
//            else begin // Has rollback events to push
//               // current event is a regular event
//               // Need a rollback event and a cancellation message
//                  if(r_rollback_msg_type == 0) begin
//                     c_rollback_msg_type = 1;
//                     c_out_event_msg = rbk_cncl_msg;
//                  end
//                  else begin
//                     c_rollback_msg_type = 0;
//                     c_out_event_msg = rbk_evt_msg;
//                     c_out_buf_rd_en = 1;
//                  end 
//            end
//         end
//      end 
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
         r_out_event_msg <= c_out_event_msg | {finalize, {MSG_WID-1{1'b0}}};
         r_rollback_msg_type <= c_rollback_msg_type;
      end 
      
      r_core_ready <= rst_n ? (c_state == IDLE) : 0;
   end
   
   
   localparam HIST_IDLE = 0;
   localparam HIST_REQ = 1;
   localparam HIST_RECV = 2;
   localparam HIST_WAIT = 3;
   
   reg [1:0] c_hist_state, r_hist_state;
   
   
   always @* begin // FSM: read hist table
      c_hist_done = 0;
      c_hist_state = r_hist_state;
      c_hist_rq = 0;
      c_hist_addr = cur_lp_id * (2 ** NB_HIST_DEPTH) + r_hist_cnt;
      c_hist_cnt = r_hist_cnt;
      c_hist_wr = 0;
      
      case (r_hist_state)
      HIST_IDLE: begin
         if(r_state == READ_HIST ) begin
            if(r_hist_size > 0)
               c_hist_state = HIST_REQ;
            else
               c_hist_done = 1;
         end
         else if(r_state == WRITE_HIST) begin
            if(hist_buf_ret_size > 0) 
               c_hist_state = HIST_REQ;
            else
               c_hist_done = 1;
         end
      end
   
      HIST_REQ: begin
         c_hist_rq = 1'b1;
         c_hist_wr = (r_state == WRITE_HIST);
         
         c_hist_state = HIST_WAIT;
      end
      
      HIST_WAIT: begin
         c_hist_rq = 1;
         c_hist_wr = (r_state == WRITE_HIST);
         if(hist_access_grant) begin
            c_hist_rq = 0;
            c_hist_wr = 0;
            c_hist_cnt = r_hist_cnt + 1;
            if(r_state == READ_HIST) begin
               if(r_hist_cnt == r_hist_size - 1) begin
                  c_hist_state = HIST_IDLE;
                  c_hist_done = 1;
               end
               else begin
                  c_hist_state = HIST_REQ;
               end
            end
            else if(r_state == WRITE_HIST) begin
               if(r_hist_cnt == hist_buf_ret_size - 1) begin
                  c_hist_done = 1;
                  c_hist_state = HIST_IDLE;
               end
               else 
                  c_hist_state = HIST_REQ;
            end
         end
      end
      
      endcase
         
   end
   
   reg r_hist_data_vld;
      
   always @(posedge clk) begin
      r_hist_state <= rst_n ? c_hist_state : HIST_IDLE;
      r_hist_data_rd <= hist_access_grant ? hist_data_rd : r_hist_data_rd;
      r_hist_data_vld <= (hist_access_grant && r_state == READ_HIST) ;
      r_hist_data_wr <= hist_buf_data;
   end
   
   // Memory access control
   always @(posedge clk) begin
      if (~rst_n || r_state == IDLE || r_state == GEN_EVT) begin
         ld_mem_counter <= 0;
         st_mem_counter <= 0;
         ld_rtn_counter <= 0;
      end
      else begin
         if(ld_rtn_vld || st_rtn_vld)
            ld_rtn_counter <= ld_rtn_counter  + 1;
         
         if(mem_gnt)
            ld_mem_counter <= ld_mem_counter + 1;
      end
   end
   
   
   // Superimpose the buffer size on message, to be read by core monitor  
   assign out_event_msg = r_out_event_msg | {1'b0, hist_buf_ret_size, {MSG_WID-NB_HIST_DEPTH-1{1'b0}} };
   
   // Rollback entry information
   localparam RBK_OFFSET_WID =7;
   localparam RBK_TYPE_WID = 1;
   
   wire [TIME_WID-1:0] rbk_time;
   wire [NB_LPID-1:0] rbk_target, rbk_lp;
   wire [RBK_OFFSET_WID-1:0] rbk_offset;
   wire [RBK_TYPE_WID-1:0] rbk_type;

   assign rbk_time   = out_buf_dout[0 +: TIME_WID];
   assign rbk_lp     = cur_lp_id;
   assign rbk_type   = out_buf_dout[(TIME_WID) +: RBK_TYPE_WID];
   assign rbk_offset = out_buf_dout[(TIME_WID + RBK_TYPE_WID) +: RBK_OFFSET_WID];
   assign rbk_target = out_buf_dout[(TIME_WID + RBK_TYPE_WID + RBK_OFFSET_WID) +: NB_LPID];

   assign null_msg      = { {MSG_WID-EVT_TYPE_WID-NB_LPID-TIME_WID{1'b0}}, CANCEL_EVT, {NB_LPID + TIME_WID{1'b0}} };
   assign rbk_evt_msg   = { {MSG_WID-EVT_TYPE_WID-NB_LPID-TIME_WID{1'b0}}, REGULAR_EVT, rbk_lp, rbk_time};
   assign rbk_cncl_msg  = { {MSG_WID-EVT_TYPE_WID-NB_LPID-TIME_WID{1'b0}}, CANCEL_EVT, rbk_target, (rbk_time + rbk_offset)}; 
   
	assign ready = r_core_ready;
	assign ld_rtn_vld = r_rs_vld && (r_rs_cmd == MCAE_CMD_RD8_DATA) &&
							(r_rs_rtnctl[0 +: NB_COREID] ==  core_id);
	assign st_rtn_vld = r_rs_vld && (r_rs_cmd == MCAE_CMD_WR_CMP) &&
							(r_rs_rtnctl[0 +: NB_COREID] == core_id);
							
	always @(posedge clk) begin
      r_rs_vld  <= (~rst_n) ? 1'b0 : mc_rs_vld;
      r_rs_cmd  <= (~rst_n) ? 'd0 : mc_rs_cmd;
      r_rs_rtnctl <= (~rst_n) ? 'd0 : mc_rs_rtnctl;
      r_rs_data  <= (~rst_n) ? 'd0 : mc_rs_data;
      r_mc_rq_stall <= mc_rq_stall;
      r_hist_filt_done1 <= (r_state == READ_HIST) ? c_hist_done : 0;
      r_hist_filt_done2 <= rst_n ? r_hist_filt_done1 : 0;
      hist_buf_ret_size <= (~rst_n || r_state == IDLE) ? 0 : 
                              (c_gen_next_evt ? hist_buf_ret_size + 1 : 
                                 (r_hist_filt_done2 ? hist_buf_cnt : hist_buf_ret_size));
      r_hist_size <= stall ? 0 : hist_size;
      
   end
   
   // random delay generation
   reg [7:0] delay_counter;
   always @(posedge clk) begin 
      delay_counter <= (r_state == PROC_DELAY) ? delay_counter + 1 : 0; 
   end
   assign rand_delay_reached = (delay_counter >= rnd[2*(NB_RND/3) +: 4] + fixed_delay);
	
	reg [2:0] counter;
	always@(posedge clk) begin
		r_state <= (rst_n) ? c_state : 1'b0;
		counter <= (rst_n) ? 
						(r_state == WRITE_HIST ? counter + 1 : 3'b0) : 3'b0; 
		
		new_event_ready <= rst_n ? c_event_ready : 0;
		new_event_time <= cur_event_time + 10 + rnd [0*(NB_RND/3) +: 6]; // Keep at least 10 units time gap between events
		new_event_target <= rnd[1*(NB_RND/3) +: NB_LPID] & lp_mask; 
		r_rq_vld <= rst_n ? c_rq_vld : 0; 
		r_rq_cmd <= c_rq_cmd;
      r_rq_vadr <= c_rq_vadr;
      r_rtn1 <= rst_n ? c_rtn1 : 0;
      r_rtn2 <= rst_n ? c_rtn2 : 0;
      rtn_data[63:0] <= rst_n ? (ld_rtn_vld ? r_rs_data : rtn_data[63:0]) : 0;
	end
	
   always @(posedge clk) begin 
      r_hist_cnt <= r_hist_state == IDLE ? 0 : c_hist_cnt;
      r_hist_rq <= rst_n ? c_hist_rq : 0;
      r_hist_wr <= rst_n ? c_hist_wr : 0;
      r_hist_addr <= c_hist_addr;
      
//      if(r_state == WRITE_HIST && hist_rq) $display("Writing: core %h, address %h, data %h", core_id, hist_addr, hist_data_wr);
//      if(r_state == READ_HIST && hist_rq) $display("Reading: core %h, address %h, data %h", core_id, hist_addr, hist_data_rd);      
   end

   assign hist_data_wr = r_hist_data_wr;
      assign hist_addr = r_hist_addr;
   assign hist_wr_en = r_hist_wr;
   assign hist_rq = r_hist_rq;
   
   
   wire [TIME_WID-1:0] new_event_time_offest;
   wire [31:0] hist_buf_din;
   
   assign new_event_time_offest = new_event_time - cur_event_time;
   
   assign hist_buf_wr_en = (r_hist_data_vld && ~c_discard_hist_entry) ||
                              c_gen_next_evt;
   assign hist_buf_din = c_gen_next_evt ? 
                                 {new_event_target , new_event_time_offest[6:0], cur_event_type, cur_event_time}
                                 : r_hist_data_rd;
   assign hist_buf_rd_en = r_hist_wr & hist_access_grant;
   
   fwft_fifo #(
      .WIDTH(32),
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
   wire [TIME_WID-1:0] hist_time; 
   assign hist_time = r_hist_data_rd[0 +: TIME_WID];
   wire hist_type;
   assign hist_type = r_hist_data_rd[TIME_WID +: RBK_TYPE_WID]; // 1 = Cancellation Event, 0 = regular event
   wire [RBK_OFFSET_WID-1:0] hist_offset;
   assign hist_offset = r_hist_data_rd[TIME_WID + RBK_TYPE_WID +: RBK_OFFSET_WID];
   wire [NB_LPID-1:0] hist_target;
   assign hist_target = r_hist_data_rd[TIME_WID + RBK_TYPE_WID + RBK_OFFSET_WID +: NB_LPID];
   reg c_cancel_match_found, r_cancel_match_found;
   reg c_gen_rollback;
   
   always @* begin 
      c_discard_hist_entry = 0;
      c_cancel_match_found = r_cancel_match_found;
      c_discard_cur_evt = r_discard_cur_evt;
      c_gen_rollback = 0;
      c_gen_cancel = r_gen_cancel;
      if(r_hist_data_vld) begin
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
            if(cur_event_type == CANCEL_EVT) begin 
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
                              (c_gen_cancel && ~r_gen_cancel ? 
                                 { {EVT_TYPE_WID{1'b1}}, hist_target, hist_time + hist_offset } : cancel_evt_msg);
      r_gen_cancel <= (r_state == IDLE) ? 0 : c_gen_cancel;
   end 
   
   wire out_buf_wr_en;
   assign out_buf_wr_en = c_gen_rollback;
   assign out_buf_din = r_hist_data_rd;
                           
   fwft_fifo #(
      .WIDTH(32),
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
   
   // Counters
   reg [15:0] r_proc_time, r_mem_time;
   reg ack_rcvd;
   always @(posedge clk) begin
      if(~rst_n) begin
         r_proc_time <= 0;
         r_mem_time <= 0;
         ack_rcvd <= 0;
      end
      else begin
         if(ack)
            ack_rcvd <= 0;
         r_proc_time <= (r_state == IDLE || ack_rcvd) ? 0 : r_proc_time + 1;
         
         if(r_state == IDLE || ack_rcvd)
            r_mem_time <= 0;
         else
            r_mem_time <= (r_state == LD_MEM || r_state == LD_RTN || r_state == ST_MEM || r_state == ST_RTN) ?
                              r_mem_time + 1 : r_mem_time;
      end
   end
   
   assign proc_time = r_proc_time;
   assign mem_time = r_mem_time;
   
endmodule
