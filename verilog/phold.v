module phold #(
   parameter    NUM_MC_PORTS = 1,
   parameter    MC_RTNCTL_WIDTH = 32, // Width of timestamps
   parameter    TIME_WID = 16
   )(
   input clk,

   input [47:0]	addr,
   input [TIME_WID-1:0] sim_end,
   input [8:0] num_init_events,
   input [7:0] lp_mask,
   input [3:0] num_memcall,
   input [7:0] fixed_delay,
   input [63:0] core_mask,
   
   output reg [TIME_WID-1:0] gvt,
   output reg rtn_vld,
   output reg cleanup,

   output			mc_rq_vld,
   output [2:0]	mc_rq_cmd,
   output [3:0]	mc_rq_scmd,
   output [47:0]	mc_rq_vadr,
   output [1:0]	mc_rq_size,
   output [MC_RTNCTL_WIDTH-1:0]	mc_rq_rtnctl,
   output [63:0]	mc_rq_data,
   output 			mc_rq_flush,
   input			mc_rq_stall,

   input			mc_rs_vld,
   input  [2:0]	mc_rs_cmd,
   input  [3:0]	mc_rs_scmd,
   input  [MC_RTNCTL_WIDTH-1:0]	mc_rs_rtnctl,
   input  [63:0]	mc_rs_data,
   output			mc_rs_stall,
   
   output [63:0] total_cycles,
   output [63:0] total_events,
   output [63:0] total_stalls,
   output [63:0] total_antimsg,
   output [63:0] total_q_conf,
   output [63:0] mem_hist_conf,
   output [63:0] avg_proc_time,
   output [63:0] avg_mem_time,
   output [63:0] avg_hist_time,
   
   input rst_n
   );

   localparam MSG_WID = 32;         // Width of event message
   localparam NUM_CORE =  64;
   localparam NB_COREID = 6;
   localparam NUM_LP = 256;
   localparam NB_LPID = 8;
   // Need to re-generate the core if History table parameters change.
   localparam HIST_WID = 32;
   localparam NB_HIST_DEPTH = 4; // Depth of history buffer reserved for each LP = 2**NB_HIST_DEPTH
   localparam NB_HIST_ADDR = NB_HIST_DEPTH + NB_LPID;  // Bits to address the whole history memory, whole size = NUM_LP * (2**NB_HIST_DEPTH)
   
   localparam NB_RAND = 24;

   localparam NUM_MEM_BYTE = 8;


   // Registering Mem Interface
   reg         r_mc_rq_vld;
   reg [2:0]   r_mc_rq_cmd;
   reg [3:0]   r_mc_rq_scmd;
   reg [47:0]  r_mc_rq_vadr;
   reg [1:0]   r_mc_rq_size;
   reg [MC_RTNCTL_WIDTH-1:0]  r_mc_rq_rtnctl;
   reg [63:0]  r_mc_rq_data;
   reg         r_mc_rq_flush;
   reg       r_mc_rq_stall;

   reg       r_mc_rs_vld;
   reg  [2:0]   r_mc_rs_cmd;
   reg  [3:0]   r_mc_rs_scmd;
   reg  [MC_RTNCTL_WIDTH-1:0]  r_mc_rs_rtnctl;
   reg  [63:0]  r_mc_rs_data;
   reg         r_mc_rs_stall;


   wire [MSG_WID-1:0] msg;
   wire sent_msg_vld;
   wire rcv_msg_vld;
   wire [NUM_CORE-1:0] stall;
   wire [TIME_WID-1:0] min_time;
   wire min_time_vld;
   wire [NB_COREID-1:0] core_id;

   wire q_full;
   wire q_empty;

/*
 * State Machine
 */
localparam 	IDLE = 3'd0,
         INIT = 3'd1,
         READY = 3'd2,
         RUNNING = 3'd3,
         FINISHED = 3'd4;

wire [NUM_CORE-1:0] core_active;
wire init_complete;
reg	[2:0]	c_state, r_state;
reg c_rtn_vld;
reg block_cores;
reg c_cleanup;
   
always @* begin : state_transitions
   c_state = r_state;
   c_rtn_vld = rtn_vld;
   block_cores = 0;
   c_cleanup = 0;

   case(r_state)
   IDLE:
      if(rst_n)
         c_state = INIT;
   INIT:
      if(init_complete) begin
         c_state = READY;
      end
   READY:
      c_state = RUNNING;
   RUNNING: begin
      if(gvt > sim_end) begin
         c_rtn_vld = 1;
         block_cores = 1;   
         if(~|core_active) begin
            c_state = FINISHED;
         end
      end
   end 
   FINISHED: begin
         c_state = IDLE;
         c_rtn_vld = 1;
         c_cleanup = 1;
   end
   endcase
end

always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
      r_state <= 0;
      rtn_vld <= 0;
      cleanup <= 0;
   end
   else begin
      r_state <= c_state;
      rtn_vld <= c_rtn_vld || q_full;
      cleanup <= c_cleanup || q_full;
   end
end


/*
 *  Initialization state.
 *  Used to insert the initial events to the queue.
 */
reg [9:0] init_counter;
always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
      init_counter <= 0;
   end
   else begin
      init_counter <= (r_state == INIT) ? (init_counter + 1) : 0;
   end
end
assign init_complete = (init_counter == {(num_init_events -1), 1'b0} );


/*
 *	Events enqueue and dispatch control
 */
wire enq, deq;
wire [MSG_WID-1:0] queue_out;
wire  [MSG_WID-1:0] new_event;
wire [8:0]	event_count; // It's used to display debug statements

wire new_event_available, core_available;
wire [NB_COREID-1:0] rcv_egnt, send_egnt;
wire [NUM_CORE-1:0] rcv_vgnt, send_vgnt, rcv_vld, send_vld;
wire [MSG_WID-1:0] new_event_data[0:NUM_CORE-1];
wire  [MSG_WID-1:0] send_event_data;

reg [NB_COREID-1:0] rcv_sel, send_sel;
reg [MSG_WID-1:0] r_rcv_msg [0:NUM_CORE-1];
reg [MSG_WID-1:0] r_send_msg;
reg r_rcv_vld; 
reg r_send_req;

reg queue_busy;
wire deq_success = (r_state == RUNNING) & ~enq && ~queue_busy && ~q_empty && r_send_req;
wire [NUM_CORE-1:0] rcv_ack = enq << rcv_sel;
wire [NUM_CORE-1:0] event_sent = deq_success << send_sel;

assign enq = queue_busy ? 0 : 
            ( (r_state == INIT) | ((r_state == RUNNING) ? (~q_full && r_rcv_vld) : 1'b0) );
//assign deq = (r_state == RUNNING) ? (~new_event_available && ~q_empty && core_available) : 0;
assign deq = queue_busy ? 0 : ( (r_state == RUNNING) ? (~enq && ~q_empty && r_send_req) : 0);

assign new_event = (r_state == INIT) ? {(lp_mask & init_counter[1 +: NB_LPID]), {TIME_WID{1'b0}} } : r_rcv_msg[rcv_sel];


/*
 *	Submodule instantiations
 */
wire [NUM_CORE-1:0] mem_req, mem_vgnt;
wire [NB_COREID-1:0] mem_egnt;
wire mem_req_vld;
wire send_event_valid, next_rnd;
assign send_event_data = queue_out;
assign send_event_valid = deq;
assign next_rnd = deq || (r_state == INIT);

// Round robin arbiter
rrarb #(.NR(NUM_CORE), .PIPE(0))  rcv_rrarb (	// Receive new events from the cores
   .clk    ( clk ),
   .reset  ( ~rst_n ),
   .req    ( rcv_vld ),
   .stall  ( 1'b0 ),
   .vgnt   ( rcv_vgnt ),
   .eval   ( new_event_available ),
   .egnt   ( rcv_egnt )
);

rrarb #(.NR(NUM_CORE), .PIPE(0))  send_rrarb (	// Dispatch new events to the cores
   .clk    ( clk ),
   .reset  ( ~rst_n ),
   .req    ( send_vld ),
   .stall  ( 1'b0 ),
   .vgnt   ( send_vgnt ),
   .eval   ( core_available ),
   .egnt   ( send_egnt )
);

always @(posedge clk) begin : q_prep
   integer i;
   send_sel <= send_egnt;
   rcv_sel <= rcv_egnt;
   r_rcv_vld <= new_event_available;
   r_send_req <= (|send_vld) && ~block_cores;
   
   r_send_msg <= send_event_data;
   for(i=0; i < NUM_CORE; i = i + 1) begin
      r_rcv_msg[i] <= new_event_data[i];
   end 
end


rrarb #(.NR(NUM_CORE), .PIPE(1)) mem_rrarb (	// Memory access arbiter
   .clk    ( clk ),
   .reset  ( ~rst_n ),
   .req    ( mem_req ),
   .stall  ( mem_req[mem_egnt] && mem_vgnt[mem_egnt] ),
   .vgnt   ( mem_vgnt ),
   .eval   ( mem_req_vld ),
   .egnt   ( mem_egnt )
   );

wire [NUM_CORE-1:0] hist_req, hist_vgnt;
wire [NB_COREID-1:0] hist_egnt;
wire hist_req_vld;

rrarb #(.NR(NUM_CORE), .PIPE(1))  history_arbiter (   // Event history table arbiter
   .clk    ( clk ),
   .reset  ( ~rst_n ),
   .req    ( hist_req ),
   .stall  ( 1'b0 ),
   .vgnt   ( hist_vgnt ),
   .eval   ( hist_req_vld ),
   .egnt   ( hist_egnt )
   );

wire [NUM_CORE-1:0]  hist_wr_en;
wire [NB_HIST_ADDR-1:0]  hist_addr[NUM_CORE-1:0];
wire [HIST_WID-1:0] hist_data_wr[NUM_CORE-1:0];
wire [HIST_WID-1:0] hist_data_rd;

//bram_sp_32 event_history_table(
//      .clka (~clk ), // input clka
//      .wea  (hist_wea && hist_req_vld), // input [0 : 0] wea
//      .addra(hist_addra), // input [7 : 0] addra
//      .dina (hist_dina), // input [31 : 0] dina
//      .douta(hist_data_rd)  // output [31 : 0] douta
//   );

// Buffering history table input and output
reg [NUM_CORE-1:0] r_hist_vgnt;
reg [NB_HIST_ADDR-1:0] r_hist_addr[NUM_CORE-1:0];
// reg [HIST_WID-1:0] r_hist_din_val;
reg [NB_COREID-1:0] r_hist_egnt;
reg [NUM_CORE-1:0] r_hist_wea;
reg r_hist_req_vld;
reg [HIST_WID-1:0] r_hist_data_wr[NUM_CORE-1:0];
reg [HIST_WID-1:0] r_hist_data_rd;

always @(posedge clk) begin :hist_assignment
   integer hi;
   for(hi = 0; hi < NUM_CORE; hi = hi+1) begin
      r_hist_addr[hi] <= hist_addr[hi];
      r_hist_data_wr[hi] <= hist_data_wr[hi];
   end 
   r_hist_wea <= hist_wr_en;
   r_hist_req_vld <= hist_req_vld;
   
   r_hist_vgnt <= hist_vgnt;
   r_hist_egnt <= hist_egnt;
//   r_hist_din_val <= hist_data_wr[hist_egnt];
   r_hist_data_rd <= hist_data_rd;
end

wire  hist_wea = r_hist_wea[r_hist_egnt] && r_hist_req_vld; // history table write enable

hist_table #(
   .WIDTH(HIST_WID),
   .DEPTH(2 ** NB_HIST_ADDR),
   .ADDR_WID (NB_HIST_ADDR)
   )
   history_table(
      .clka (clk ), // input clka
      .wea  (hist_wea), // input [0 : 0] wea
      .addra(r_hist_addr[r_hist_egnt]), // input [7 : 0] addra
      .dina (r_hist_data_wr[r_hist_egnt]), // input [31 : 0] dina
      .douta(hist_data_rd)  // output [31 : 0] douta
   );

wire [NB_RAND-1:0] random_in; 

reg [NB_LPID-1:0] r_lp_mask;
reg [3:0] r_num_memcall;
reg [7:0] r_fixed_delay;

always @(posedge clk) begin
   r_lp_mask <= lp_mask[0 +: NB_LPID];
   r_num_memcall <= num_memcall[3:0];
   r_fixed_delay <= fixed_delay;
end


wire [NUM_CORE-1:0] p_mc_rq_vld;
wire [2:0] p_mc_rq_cmd[NUM_CORE-1:0];
wire [3:0] p_mc_rq_scmd[NUM_CORE-1:0];
wire [47:0] p_mc_rq_vadr[NUM_CORE-1:0];
wire [1:0] p_mc_rq_size[NUM_CORE-1:0];
wire [MC_RTNCTL_WIDTH-1:0] p_mc_rq_rtnctl[NUM_CORE-1:0];
wire [63:0] p_mc_rq_data[NUM_CORE-1:0];
wire [NUM_CORE-1:0] p_mc_rq_flush;
wire [NUM_CORE-1:0] p_mc_rs_stall;

wire [NB_HIST_DEPTH*NUM_CORE-1:0] core_hist_cnt;

reg [15:0] r_proc_time[0:NUM_CORE-1], r_mem_time[0:NUM_CORE-1], r_stall_time[0:NUM_CORE-1], r_hist_time[0:NUM_CORE-1];

// Phold Core instantiation
genvar g;
generate
for (g = 0; g < NUM_CORE; g = g+1) begin : gen_phold_core
   wire event_valid, new_event_ready, ack, ready;
   wire [NB_LPID-1:0] new_event_target;
   wire [TIME_WID-1:0] new_event_time;
   
   wire [15:0] proc_time, mem_time, stall_time, hist_access_time;

   wire t_rq;
   wire req_event;
   
   reg r_hist_ack; // One cycle delayed history access grant
   always @(posedge clk) begin
      r_hist_ack <= r_hist_vgnt[g];
   end
   
   phold_core
    #(.NUM_MEM_BYTE    ( NUM_MEM_BYTE ),
      .MC_RTNCTL_WIDTH ( MC_RTNCTL_WIDTH ),
      .NB_COREID       ( NB_COREID ),
      .NB_LPID         ( NB_LPID ),
      .NB_HIST_ADDR    ( NB_LPID + NB_HIST_DEPTH ),
      .NB_HIST_DEPTH   ( NB_HIST_DEPTH )
   )  phold_core_inst
    (
      .clk              ( clk ),
      .rst_n            ( rst_n ),
      .core_id          ( g[0 +: NB_COREID] ),
      .event_valid      ( event_valid ),
      .cur_event_msg    ( r_send_msg ),
      .global_time      ( gvt ),
      .random_in        ( random_in ),
      .lp_mask          ( r_lp_mask ),
      .num_memcall      ( r_num_memcall ),
      .fixed_delay      ( r_fixed_delay ),
      
      .out_event_msg    ( new_event_data[g] ),
      .new_event_ready  ( new_event_ready ),
      .active           ( core_active[g] ),
      .stall            ( stall[g] ),
      .ready            ( ready ),
      .ack              ( ack ),
      
      .proc_time        ( proc_time ),
      .mem_time         ( mem_time  ),
      .stall_time       ( stall_time  ),
      .hist_access_time ( hist_access_time ),

      .hist_addr        ( hist_addr[g]),
      .hist_data_rd     ( r_hist_data_rd ),
      .hist_data_wr     ( hist_data_wr[g] ),
      .hist_wr_en       ( hist_wr_en[g] ),
      .hist_rq          ( t_rq ), //hist_req[g] ),
      .hist_access_grant( r_hist_ack ),
      .hist_size        ( core_hist_cnt[g*NB_HIST_DEPTH +: NB_HIST_DEPTH]),

      .mc_rq_vld        ( p_mc_rq_vld[g] ),
      .mc_rq_cmd        ( p_mc_rq_cmd[g] ),
      .mc_rq_scmd       ( p_mc_rq_scmd[g] ),
      .mc_rq_vadr       ( p_mc_rq_vadr[g] ),
      .mc_rq_size       ( p_mc_rq_size[g] ),
      .mc_rq_rtnctl     ( p_mc_rq_rtnctl[g] ),
      .mc_rq_data       ( p_mc_rq_data[g] ),
      .mc_rq_flush      ( p_mc_rq_flush[g] ),
      .mc_rq_stall      ( r_mc_rq_stall ),
      .mc_rs_vld        ( r_mc_rs_vld ),
      .mc_rs_cmd        ( r_mc_rs_cmd ),
      .mc_rs_scmd       ( r_mc_rs_scmd ),
      .mc_rs_rtnctl     ( r_mc_rs_rtnctl ),
      .mc_rs_data       ( r_mc_rs_data ),
      .mc_rs_stall      ( p_mc_rs_stall[g] ),
      .addr             ( addr ),
      .mem_gnt          ( mem_vgnt[g] )
   )/* synthesis syn_noprune=1 */;

   // assign event_valid = send_event_valid & send_vgnt[g] & ~queue_busy;
   assign rcv_vld[g] = new_event_ready;
   assign ack = rcv_ack[g]; //rcv_vgnt[g] & ~q_full & ~queue_busy;
//   assign send_vld[g] = ready;
   
   // To improve timing for event dispatch
   req_buffer u_sendbuf(clk, ready && core_mask[g], send_vld[g], event_sent[g], event_valid, ~rst_n);
   
   // History table timing improvement buffer
   req_buffer u_reqbuf(clk, t_rq, hist_req[g], hist_vgnt[g], , ~rst_n);
   
   always @(posedge clk) begin
      r_proc_time[g] <= proc_time;
      r_mem_time[g] <= mem_time;
      r_stall_time[g] <= stall_time;
      r_hist_time[g] <= hist_access_time;
   end
   
end
endgenerate

wire prio_q_enq;
/* Prevent enqueue of null message(equivalent to {1'b1, 19'b0}) */
assign prio_q_enq = enq && (new_event[0 +: NB_LPID + TIME_WID + 1] != {1'b1, {NB_LPID + TIME_WID{1'b0}} });

// Shuffle position of Event type flag and flip the bit, so that it counts as smaller timestamp in queue
wire  [MSG_WID-1:0] new_event_temp, queue_out_temp;
assign new_event_temp = {new_event[TIME_WID +: NB_LPID], new_event[0 +: TIME_WID], ~new_event[TIME_WID + NB_LPID]};
assign queue_out = {~queue_out_temp[0], queue_out_temp[TIME_WID+1 +: NB_LPID], queue_out_temp[1 +: TIME_WID]}; 

always @(posedge clk) begin
   queue_busy <= rst_n ? (enq | deq) : 0;
end

// Event queue instantiation
prio_q_mult #(.CMP_WID(TIME_WID+1)) queue(
   .clk(clk),
   .rst_n(rst_n),
   .enq(prio_q_enq),
   .deq( deq ),
   .inp_data(new_event_temp),
   .out_data(queue_out_temp),
   .full( q_full ),
   .empty( q_empty ),
   .elem_cnt(event_count)
);

// PRNG instantiation
wire [47:0] seed = 48'h66668888aaaa; // Initialize PRNG with a seed
LFSR prng (
   .clk   ( clk ),
   .rst_n ( rst_n ),
   .next  ( next_rnd ),
   .seed  ( seed ),
   .rnd   ( random_in )
   );

   assign sent_msg_vld = deq;
   assign rcv_msg_vld = enq;
   assign msg = sent_msg_vld ? queue_out : (rcv_msg_vld ? new_event : 0);
   assign core_id = sent_msg_vld ? send_sel : (rcv_msg_vld ? rcv_sel: 0);

   core_monitor #(
      .NUM_CORE(NUM_CORE),
      .NB_COREID( NB_COREID ),
      .NUM_LP  (NUM_LP  ),
      .NB_LPID ( NB_LPID ),
      .TIME_WID(TIME_WID),
      .MSG_WID (MSG_WID ),
      .NB_HIST_DEPTH(NB_HIST_DEPTH)
   ) u_core_monitor (
      .clk         (clk         ),
      .msg         (msg         ),
      .sent_msg_vld(sent_msg_vld),
      .rcv_msg_vld (rcv_msg_vld ),
      .core_id     (core_id     ),
      .core_active (core_active ),
      .stall       (stall       ),
      .min_time    (min_time    ),
      .min_time_vld(min_time_vld),
      .core_hist_cnt(core_hist_cnt),
      .reset       ( ~rst_n )
   );

   
   always @(posedge clk) begin
      r_mc_rs_vld <= mc_rs_vld;
      r_mc_rs_cmd <= mc_rs_cmd;
      r_mc_rs_scmd <= mc_rs_scmd;
      r_mc_rs_rtnctl <= mc_rs_rtnctl;
      r_mc_rs_data <= mc_rs_data;
      r_mc_rq_stall <= mc_rq_stall;
      
      r_mc_rq_vld <= mem_req_vld;
      r_mc_rq_cmd <= p_mc_rq_cmd[mem_egnt];
      r_mc_rq_scmd <= p_mc_rq_scmd[mem_egnt];
      r_mc_rq_vadr <= p_mc_rq_vadr[mem_egnt];
      r_mc_rq_size <= p_mc_rq_size[mem_egnt];
      r_mc_rq_rtnctl <= p_mc_rq_rtnctl[mem_egnt];
      r_mc_rq_data <= p_mc_rq_data[mem_egnt];
      r_mc_rq_flush <= p_mc_rq_flush[mem_egnt];
      r_mc_rs_stall <= p_mc_rs_stall[mem_egnt];
   end   
   
   assign mem_req = p_mc_rq_vld;
   assign mc_rq_vld = r_mc_rq_vld;
   assign mc_rq_cmd = r_mc_rq_cmd;
   assign mc_rq_scmd = r_mc_rq_scmd;
   assign mc_rq_vadr = r_mc_rq_vadr;
   assign mc_rq_size = r_mc_rq_size;
   assign mc_rq_rtnctl = r_mc_rq_rtnctl;
   assign mc_rq_data = r_mc_rq_data;
   assign mc_rq_flush = r_mc_rq_flush;
   assign mc_rs_stall = r_mc_rs_stall;
   
/*
 *	GVT calculation
 */
 wire [TIME_WID-1:0] c_gvt;
 reg [TIME_WID-1:0] last_queue_min_time;
 wire [TIME_WID-1:0] min_queue_vals;
 reg last_queue_empty;

 reg [TIME_WID-1:0] q_min_time;
 always @(posedge clk or negedge rst_n) begin
   if(~rst_n) begin
      gvt <= 0;
      last_queue_min_time <= 0;
      last_queue_empty <= 0;
   end
   else begin
      last_queue_empty <= q_empty;
      last_queue_min_time <= queue_out[0 +: TIME_WID];
      gvt <= (r_state == RUNNING && min_time_vld) ? c_gvt : gvt;
   end
 end
 
 assign min_queue_vals = (!q_empty && !last_queue_empty) ? 
                              (queue_out[0 +: TIME_WID] < last_queue_min_time ? queue_out[0 +: TIME_WID] : last_queue_min_time) :
                                 (!last_queue_empty ? last_queue_min_time : queue_out[0 +: TIME_WID]);
 
 wire min_queue_vld;
 assign min_queue_vld = !last_queue_empty || !q_empty;
 

// assign c_gvt = (min_time_vld && min_queue_vld) ?
//                     (min_time < min_queue_vals ? min_time : min_queue_vals) :
//                        (min_time_vld ? min_time : min_queue_vals);

assign c_gvt = q_min_time < min_time ? q_min_time : min_time;
 
always @(posedge clk) begin
   if(~rst_n) begin
      q_min_time <= {TIME_WID{1'b1}};
   end
   else begin
      if(min_time_vld && !q_empty)
         q_min_time <= queue_out[0 +: TIME_WID];
      else if(!q_empty)
         q_min_time <= q_min_time < queue_out[0 +: TIME_WID] ? q_min_time : queue_out[0 +: TIME_WID];   
   end
   
end 

// Counts And Statistics
/* Total Cycles*/
reg [63:0] r_num_cycles;
reg [63:0] r_total_events;
reg [63:0] r_anti_msg_total;
reg [20:0] r_q_conflict_all, r_q_conflict_send, r_q_conflict_rcv;
reg [31:0] r_mem_conflict, r_hist_conflict;
reg r_evt_sent;
reg r_evt_rcv;
reg r_cncl_evt;

reg [NUM_CORE-1:0] r_req_s, r_req_r;
wire [NUM_CORE-1:0] r_req = r_req_s | r_req_r;

always @(posedge clk) begin
   r_evt_sent <= deq;
   r_evt_rcv <= enq;
   r_cncl_evt <= ~queue_out_temp[0];
   r_req_s <= send_vld;
   r_req_r <= rcv_vld;
   
   r_q_conflict_all <= rst_n ? 
                        ( ( ~queue_busy && (r_rcv_vld && r_send_req) && |(r_req & (r_req - 1)) && (r_state == RUNNING) )
                                 ? r_q_conflict_all + 1 : r_q_conflict_all ) : 0;
   
   r_q_conflict_send <= rst_n ? 
                        ( (~queue_busy && r_send_req && |(r_req_s & (r_req_s - 1)) && (r_state == RUNNING) )
                                 ? r_q_conflict_send + 1 : r_q_conflict_send ) : 0;
   
   r_q_conflict_rcv <= rst_n ? 
                        ( (~queue_busy && r_rcv_vld && |(r_req_r & (r_req_r - 1)) ) ? r_q_conflict_rcv + 1 : r_q_conflict_rcv ) : 0;
   
   r_mem_conflict <= rst_n ? 
                        ( |(mem_req & (mem_req - 1)) ? r_mem_conflict + 1 : r_mem_conflict ) : 0;
   
   r_hist_conflict <= rst_n ? 
                        ( |(hist_req & (hist_req - 1)) ? r_hist_conflict + 1 : r_hist_conflict ) : 0;
   
   r_num_cycles <= rst_n ? ( (r_state == RUNNING) ? r_num_cycles + 1 : r_num_cycles) : 0;
   r_total_events <= rst_n ? ( r_evt_sent ? r_total_events + 1 : r_total_events ) : 0;
   r_anti_msg_total <= rst_n ? (r_evt_sent && r_cncl_evt ? r_anti_msg_total + 1 : r_anti_msg_total) : 0; 
   
end

wire req_test = |(r_req_r & (r_req_r - 1));
wire send_test = |(r_req_s & (r_req_s - 1));

assign total_cycles = r_num_cycles;
assign total_events = r_total_events;
assign total_antimsg = r_anti_msg_total;
assign total_q_conf = {(r_q_conflict_all >>3), (r_q_conflict_rcv >> 3), (r_q_conflict_send >> 3)};
assign mem_hist_conf = { r_mem_conflict, r_hist_conflict};

reg [NUM_CORE-1:0] r_core_stalled, r_rcv_ack;
reg [63:0] core_stall_time[0:NUM_CORE-1];
reg [63:0] r_total_stalls;

reg core_quitting;
reg [NB_COREID-1:0] r_last_sel;

generate
   genvar r;
   for(r = 0; r < NUM_CORE; r = r+1) begin
      always @(posedge clk) begin
         if(~rst_n)
            core_stall_time[r] <= 0;
         else if(r_rcv_ack[r] && core_quitting)
            core_stall_time[r] <= 0;
         else if(r_core_stalled[r])
            core_stall_time[r] <= core_stall_time[r] + 1;
      end
   end
endgenerate

// Average Times
reg [63:0] total_proc_time, total_mem_time, total_hist_time;

always @(posedge clk) begin
   r_rcv_ack <= rcv_ack;
   r_core_stalled <= stall;
   core_quitting <= new_event[MSG_WID-1] && enq;
   r_last_sel <= rcv_sel;
   
   if(~rst_n) begin
      total_proc_time <= 0;
      r_total_stalls <= 0;
      total_mem_time <= 0;
      total_hist_time <= 0;
   end
   else if(core_quitting) begin
      total_proc_time <= total_proc_time + r_proc_time[r_last_sel];
      r_total_stalls <= r_total_stalls + r_stall_time[r_last_sel];
      total_mem_time <= total_mem_time + r_mem_time[r_last_sel];
      total_hist_time <= total_hist_time + r_hist_time[r_last_sel];
   end 
end

assign total_stalls = r_total_stalls;
assign total_stalls = r_total_stalls;

assign avg_proc_time = total_proc_time;
assign avg_mem_time = total_mem_time;
assign avg_hist_time = total_hist_time;


`ifdef TRACE
 always @(posedge clk) begin : trace
    integer i;

    $write("GVT:%5d ",gvt);
    for(i=0; i<NUM_CORE; i=i+1) begin
       if(send_sel == i && deq) begin
          $write("|%1d->%-5d", send_event_data[TIME_WID +: NB_LPID], send_event_data[0 +: TIME_WID]);
          if(send_event_data[NB_LPID + TIME_WID]) $write("# ");
          else $write("> ");
       end
       else $write("|          ");

       if(core_active[i]) begin
          $write("%1d", u_core_monitor.core_LP_id[i]);
          if(u_core_monitor.stall[i]) $write("*");
          else $write(" ");
       end
       else
          $write("x ");

       if(rcv_sel == i && enq)
          if(new_event[0 +: NB_LPID + TIME_WID + 1] == {1'b1, {NB_LPID + TIME_WID{1'b0}}}) $write(">>########|");
          else begin
             if(new_event[NB_LPID + TIME_WID]) $write("#");
             else $write(" ");
             $write(">%1d->%-5d|",new_event[TIME_WID +: NB_LPID], new_event[0+:TIME_WID]);
          end
       else $write("          |");
    end
    $write("Q:%2d",event_count);if(event_count >0) $write("[%5d]",queue_out[0+:TIME_WID]);
    if(enq) $write("~H:%2d", new_event[MSG_WID - NB_HIST_DEPTH +: NB_HIST_DEPTH]);
    $write("\n");

    if(event_count > 56) $display("** Warning: Event count = %2d", event_count);
 end
`endif

`ifdef ANALYSIS
   reg [63:0] cycle;
      genvar k;
      reg [31:0] stalled[0:NUM_CORE-1];
      reg [31:0] arb_delay[0:NUM_CORE-1];
      reg [31:0] memld[0:NUM_CORE-1];
      reg [31:0] memst[0:NUM_CORE-1];
      reg [31:0] total[0:NUM_CORE-1];
      wire [NUM_CORE-1:0] end_iter;
      
      wire [3:0] state [0:NUM_CORE-1]; // Number of bits is state variable
      reg [3:0] state_p[0:NUM_CORE-1];
      wire [NUM_CORE-1:0] ev_type;
//      wire [NB_LPID-1:0] core_lp [NUM_CORE-1:0];
//      wire [TIME_WID-1:0] core_time [NUM_CORE-1:0];
 
      for(k=0; k<NUM_CORE; k=k+1) begin :collect_stat
         always @(posedge clk) begin
           if(gen_phold_core[k].phold_core_inst.r_state == gen_phold_core[k].phold_core_inst.IDLE) begin
                stalled[k] <= 0;
                  arb_delay[k] <= 0;
                  memld[k] <= 0;
                  memst[k] <= 0;
                  total[k] <= 0;
            end
            else begin
               if(gen_phold_core[k].phold_core_inst.r_state == gen_phold_core[k].phold_core_inst.STALL) stalled[k] <= stalled[k] + 1;
               if(gen_phold_core[k].phold_core_inst.r_state == gen_phold_core[k].phold_core_inst.LD_MEM ||
                     gen_phold_core[k].phold_core_inst.r_state == gen_phold_core[k].phold_core_inst.ST_MEM) arb_delay[k] <= arb_delay[k] + 1;
               if(gen_phold_core[k].phold_core_inst.r_state == gen_phold_core[k].phold_core_inst.LD_RTN) memld[k] <= memld[k] + 1;
               if(gen_phold_core[k].phold_core_inst.r_state == gen_phold_core[k].phold_core_inst.ST_RTN) memst[k] <= memst[k] + 1;
               total[k] <= total[k] + 1;
            end
         end
         assign end_iter[k] = ((gen_phold_core[k].phold_core_inst.r_state == gen_phold_core[k].phold_core_inst.WAIT)) &&
            gen_phold_core[k].phold_core_inst.ack && gen_phold_core[k].phold_core_inst.out_buf_empty;
            assign state[k] = gen_phold_core[k].phold_core_inst.r_state;
//         assign core_lp[k] = u_core_monitor.
//         assign exec[k] = (gen_phold_core[k].phold_core_inst.c_state == gen_phold_core[k].phold_core_inst.READ_HIST) &&
//                              (gen_phold_core[k].phold_core_inst.r_state == gen_phold_core[k].phold_core_inst.STALL ||
//                               gen_phold_core[k].phold_core_inst.r_state == gen_phold_core[k].phold_core_inst.IDLE);
            assign ev_type[k] = gen_phold_core[k].phold_core_inst.cur_event_type;
      end


   always @(posedge clk) begin : analysis
      integer i;
      cycle = rst_n ? (cycle + 1) : 0;

      // Transactions
      for(i=0; i<NUM_CORE; i=i+1) begin
         state_p[i] <= state[i];
         
         if(send_sel == i && deq) begin
            $write("%8d: sent: %2d->%5d to core %2d", cycle, send_event_data[TIME_WID +: NB_LPID], send_event_data[0 +: TIME_WID], i);
            if(send_event_data[NB_LPID + TIME_WID]) $write(" (C)");
            $write(" GVT: %-5d", gvt);
            $write(" Q:%-3d", event_count-1);
            $write("\n");
         end
   
         if(rcv_sel == i && enq) begin
            if(new_event[0 +: NB_LPID + TIME_WID + 1] == {1'b1, {NB_LPID + TIME_WID{1'b0}}}) $write("%8d: null from core %2d", cycle, i);
            else begin
               $write("%8d: recv: %2d->%5d from core %2d", cycle, new_event[TIME_WID +: NB_LPID], new_event[0+:TIME_WID], i);
               if(new_event[NB_LPID + TIME_WID]) $write(" (C)");
               $write(" Q:%-3d", event_count+1);
               
            end
            if(end_iter[i])
               $write(" - stall: %-5d, mem_rq: %-5d, memld: %-5d, memst: %-5d, total: %-8d\n",stalled[i], arb_delay[i], memld[i], memst[i], total[i]);
            else
               $write("\n");
         end 
      
         if(state[i] == gen_phold_core[0].phold_core_inst.READ_HIST && state_p[i] != state[i]) begin
            $write("%8d: exec: %2d->%5d at core %2d", cycle, u_core_monitor.core_LP_id[i], u_core_monitor.core_times[i], i);
            if(ev_type[i]) $write(" (C)");
            $write("\n");
         end
       
      end
          

      // Core status
//      $write("%8d: ", cycle);
//      for(i=0; i<NUM_CORE; i=i+1) begin
//       if(core_active[i]) begin
//          $write(" %2d ", u_core_monitor.core_LP_id[i]);
//          if(u_core_monitor.stall[i]) $write("*");
//       end
//       else
//          $write("  x");
//      end
//      $write("\n");

      // Memory requests
      if(|mem_rrarb.req) $display("%8d: mem: %b", cycle, mem_rrarb.req);
      if(|history_arbiter.req) $display("%8d: hist: %b", cycle, history_arbiter.req);

   end
`endif

endmodule
