module phold #(
   parameter    NUM_MC_PORTS = 1,
   parameter    MC_RTNCTL_WIDTH = 32, // Width of timestamps
   parameter    SIM_END_TIME = 4000,  // Target GVT value when process returns
   parameter    TIME_WID = 16
   )(
   input clk,
   input rst_n,

   input [47:0]	addr,
   output reg [TIME_WID-1:0] gvt,
   output reg rtn_vld,

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
   output			mc_rs_stall
   );

   localparam MSG_WID = 32;         // Width of event message
   localparam NUM_CORE =  16;
   localparam NB_COREID = 4;
   localparam NUM_LP = 64;
   localparam NB_LPID = 6;
   // Need to re-generate the core if History table parameters change.
   localparam HIST_WID = 32;
   localparam NB_HIST_DEPTH = 4; // Depth of history buffer reserved for each LP = 2**NB_HIST_DEPTH
   localparam NB_HIST_ADDR = NB_HIST_DEPTH + NB_LPID;  // Bits to address the whole history memory, whole size = NUM_LP * (2**NB_HIST_DEPTH)
   
   localparam NB_RAND = 24;

   localparam NUM_MEM_BYTE = 8;

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

wire init_complete;
reg	[2:0]	c_state, r_state;
reg c_rtn_vld;

always @* begin : state_transitions
   c_state = r_state;
   c_rtn_vld = rtn_vld;

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
   RUNNING:
      if(gvt > SIM_END_TIME) begin
         c_state = FINISHED;
         c_rtn_vld = 1;
      end
   FINISHED: begin
      c_state = IDLE;
      c_rtn_vld = 0;
   end
   endcase
end

always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
      r_state <= 0;
      rtn_vld <= 0;
   end
   else begin
      r_state <= c_state;
      rtn_vld <= c_rtn_vld;
   end
end


/*
 *  Initialization state.
 *  Used to insert the initial events to the queue.
 */
reg [8:0] init_counter;
always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
      init_counter <= 0;
   end
   else begin
      init_counter <= (r_state == INIT) ? (init_counter + 1) : 0;
   end
end
assign init_complete = (init_counter == 8'd31);


/*
 *	Events enqueue and dispatch control
 */
wire enq, deq;
wire [MSG_WID-1:0] queue_out;
wire  [MSG_WID-1:0] new_event;
wire [5:0]	event_count; // It's used to display debug statements

wire new_event_available, core_available;
wire [NB_COREID-1:0] rcv_egnt, send_egnt;
wire [NUM_CORE-1:0] rcv_vgnt, send_vgnt, rcv_vld, send_vld;
wire [MSG_WID-1:0] new_event_data[NUM_CORE-1:0];
wire  [MSG_WID-1:0] send_event_data;

reg queue_busy;
assign enq = queue_busy ? 0 : 
            ( (r_state == INIT) | ((r_state == RUNNING) ? (~q_full && new_event_available) : 1'b0) );
//assign deq = (r_state == RUNNING) ? (~new_event_available && ~q_empty && core_available) : 0;
assign deq = queue_busy ? 0 : ( (r_state == RUNNING) ? (~enq && ~q_empty && core_available) : 0);

assign new_event = (r_state == INIT) ? {init_counter[0 +: NB_LPID], {TIME_WID{1'b0}} } : new_event_data[rcv_egnt];


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
rrarb #(.NR(NUM_CORE))  rcv_rrarb (	// Receive new events from the cores
   .clk    ( clk ),
   .reset  ( ~rst_n ),
   .req    ( rcv_vld ),
   .stall  ( 1'b0 ),
   .vgnt   ( rcv_vgnt ),
   .eval   ( new_event_available ),
   .egnt   ( rcv_egnt )
);

rrarb #(.NR(NUM_CORE))  send_rrarb (	// Dispatch new events to the cores
   .clk    ( clk ),
   .reset  ( ~rst_n ),
   .req    ( send_vld ),
   .stall  ( 1'b0 ),
   .vgnt   ( send_vgnt ),
   .eval   ( core_available ),
   .egnt   ( send_egnt )
);

rrarb #(.NR(NUM_CORE)) mem_rrarb (	// Memory access arbiter
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

rrarb #(.NR(NUM_CORE))  history_arbiter (   // Event history table arbiter
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

wire  hist_wea; // history table write enable
wire [NB_HIST_ADDR-1:0]  hist_addra;
wire [HIST_WID-1:0] hist_dina;

assign hist_wea = hist_wr_en[hist_egnt];
assign hist_addra = hist_addr[hist_egnt];
assign hist_dina = hist_data_wr[hist_egnt];

//bram_sp_32 event_history_table(
//      .clka (~clk ), // input clka
//      .wea  (hist_wea && hist_req_vld), // input [0 : 0] wea
//      .addra(hist_addra), // input [7 : 0] addra
//      .dina (hist_dina), // input [31 : 0] dina
//      .douta(hist_data_rd)  // output [31 : 0] douta
//   );

hist_table #(
   .WIDTH(HIST_WID),
   .DEPTH(2 ** NB_HIST_ADDR),
   .ADDR_WID (NB_HIST_ADDR)
   )
   history_table(
      .clka (clk ), // input clka
      .wea  (hist_wea && hist_req_vld), // input [0 : 0] wea
      .addra(hist_addra), // input [7 : 0] addra
      .dina (hist_dina), // input [31 : 0] dina
      .douta(hist_data_rd)  // output [31 : 0] douta
   );

wire [NB_RAND-1:0] random_in; 

wire [NUM_CORE-1:0] p_mc_rq_vld;
wire [2:0] p_mc_rq_cmd[NUM_CORE-1:0];
wire [3:0] p_mc_rq_scmd[NUM_CORE-1:0];
wire [47:0] p_mc_rq_vadr[NUM_CORE-1:0];
wire [1:0] p_mc_rq_size[NUM_CORE-1:0];
wire [MC_RTNCTL_WIDTH-1:0] p_mc_rq_rtnctl[NUM_CORE-1:0];
wire [63:0] p_mc_rq_data[NUM_CORE-1:0];
wire [NUM_CORE-1:0] p_mc_rq_flush;
wire [NUM_CORE-1:0] p_mc_rs_stall;

assign mem_req = p_mc_rq_vld;
assign mc_rq_vld = mem_req_vld;
assign mc_rq_cmd = p_mc_rq_cmd[mem_egnt];
assign mc_rq_scmd = p_mc_rq_scmd[mem_egnt];
assign mc_rq_vadr = p_mc_rq_vadr[mem_egnt];
assign mc_rq_size = p_mc_rq_size[mem_egnt];
assign mc_rq_rtnctl = p_mc_rq_rtnctl[mem_egnt];
assign mc_rq_data = p_mc_rq_data[mem_egnt];
assign mc_rq_flush = p_mc_rq_flush[mem_egnt];
assign mc_rs_stall = p_mc_rs_stall[mem_egnt];

wire [NB_HIST_DEPTH*NUM_CORE-1:0] core_hist_cnt;
wire [NUM_CORE-1:0] core_active;
// Phold Core instantiation
genvar g;
generate
for (g = 0; g < NUM_CORE; g = g+1) begin : gen_phold_core
   wire event_valid, new_event_ready, ack, ready;
   wire [NB_LPID-1:0] new_event_target;
   wire [TIME_WID-1:0] new_event_time;

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
      .cur_event_msg    ( send_event_data ),
      .global_time      ( gvt ),
      .random_in        ( random_in ),
      .out_event_msg    ( new_event_data[g] ),
      .new_event_ready  ( new_event_ready ),
      .active           ( core_active[g] ),
      .stall            ( stall[g] ),
      .ready            ( ready ),
      .ack              ( ack ),

      .hist_addr        ( hist_addr[g]),
      .hist_data_rd     ( hist_data_rd ),
      .hist_data_wr     ( hist_data_wr[g] ),
      .hist_wr_en       ( hist_wr_en[g] ),
      .hist_rq          ( hist_req[g] ),
      .hist_access_grant( hist_vgnt[g] ),
      .hist_size        ( core_hist_cnt[g*NB_HIST_DEPTH +: NB_HIST_DEPTH]),

      .mc_rq_vld        ( p_mc_rq_vld[g] ),
      .mc_rq_cmd        ( p_mc_rq_cmd[g] ),
      .mc_rq_scmd       ( p_mc_rq_scmd[g] ),
      .mc_rq_vadr       ( p_mc_rq_vadr[g] ),
      .mc_rq_size       ( p_mc_rq_size[g] ),
      .mc_rq_rtnctl     ( p_mc_rq_rtnctl[g] ),
      .mc_rq_data       ( p_mc_rq_data[g] ),
      .mc_rq_flush      ( p_mc_rq_flush[g] ),
      .mc_rq_stall      ( mc_rq_stall ),
      .mc_rs_vld        ( mc_rs_vld ),
      .mc_rs_cmd        ( mc_rs_cmd ),
      .mc_rs_scmd       ( mc_rs_scmd ),
      .mc_rs_rtnctl     ( mc_rs_rtnctl ),
      .mc_rs_data       ( mc_rs_data ),
      .mc_rs_stall      ( p_mc_rs_stall[g] ),
      .addr             ( addr ),
      .mem_gnt          ( mem_vgnt[g] )
   );

   assign event_valid = send_event_valid & send_vgnt[g] & ~queue_busy;
   assign rcv_vld[g] = new_event_ready;
   assign ack = rcv_vgnt[g] & ~q_full & ~queue_busy;
   assign send_vld[g] = ready;
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
pheap #(.CMP_WID(TIME_WID+1)) queue(
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
   assign core_id = sent_msg_vld ? send_egnt : (rcv_msg_vld ? rcv_egnt : 0);

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

/*
 *	GVT calculation
 */
 wire [TIME_WID-1:0] c_gvt;

 always @(posedge clk or negedge rst_n) begin
   if(~rst_n) begin
      gvt <= 0;
   end
   else begin
      gvt <= (r_state == RUNNING) ? c_gvt : gvt;
   end
 end

 assign c_gvt = (min_time_vld && !q_empty) ?
                     (min_time < queue_out[0 +: TIME_WID] ? min_time : queue_out[0 +: TIME_WID]) :
                        (min_time_vld ? min_time : queue_out[0 +: TIME_WID]);


`ifdef TRACE
 always @(posedge clk) begin : trace
    integer i;

    $write("GVT:%5d ",gvt);
    for(i=0; i<NUM_CORE; i=i+1) begin
       if(send_egnt == i && deq) begin
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

       if(rcv_egnt == i && enq)
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
         
         if(send_egnt == i && deq) begin
            $write("%8d: sent: %2d->%5d to core %2d", cycle, send_event_data[TIME_WID +: NB_LPID], send_event_data[0 +: TIME_WID], i);
            if(send_event_data[NB_LPID + TIME_WID]) $write(" (C)");
            $write(" GVT: %-5d", gvt);
            $write(" Q:%-3d", event_count-1);
            $write("\n");
         end
   
         if(rcv_egnt == i && enq) begin
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
