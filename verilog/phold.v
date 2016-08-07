module phold #(
	parameter    NUM_MC_PORTS = 1,
	parameter    MC_RTNCTL_WIDTH = 32, // Width of timestamps
   parameter    SIM_END_TIME = 8000,  // Target GVT value when process returns
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
   localparam NUM_CORE =  4;        
   localparam NUM_MEM_BYTE = 16;

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
		r_state <= 3'b0;
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
reg [1:0] init_counter;
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		init_counter <= 0;
	end
	else begin
		init_counter <= (r_state == INIT) ? (init_counter + 1) : 0;
	end
end
assign init_complete = (init_counter == 2'd3);


/*
 *	Events enqueue and dispatch control
 */
wire enq, deq;
wire [MSG_WID-1:0] queue_out;
wire  [MSG_WID-1:0] new_event;
wire [4:0]	event_count;

wire new_event_available, core_available;
wire [1:0] rcv_egnt, send_egnt;
wire [3:0] rcv_vgnt, send_vgnt, rcv_vld, send_vld;
wire [MSG_WID-1:0] new_event_data[3:0];
wire  [MSG_WID-1:0] send_event_data;

assign enq = (r_state == INIT) | 
				((r_state == RUNNING) ? new_event_available : 1'b0) ;
assign deq = (r_state == RUNNING) ? (~new_event_available & core_available) : 0;
assign new_event = (r_state == INIT) ? {init_counter, {TIME_WID{1'b0}} }:
						new_event_data[rcv_egnt];
						

// Debug displays						
always @(posedge clk) begin
	if (deq) $display("GVT: %d, \tEvent sent to CORE %d,\ttime: %d, LP: %d",
						gvt, send_egnt, event_time, event_id);
	if (enq) $display("GVT: %d, \t\t\t\t\t\tNew event from CORE %d,\ttime: %d, LP: %d",
						gvt, rcv_egnt, new_event[TIME_WID-1:0], new_event[TIME_WID +: 3]);
end


/*
 *	Submodule instantiations
 */
wire [3:0] mem_req, mem_vgnt;
wire [1:0] mem_egnt;
wire mem_req_vld;
wire send_event_valid, next_rnd;
assign send_event_data = queue_out;
assign send_event_valid = deq;
assign next_rnd = deq || (r_state == INIT);

// Round robin arbiter
rrarb  rcv_rrarb (	// Receive new events from the cores
	.clk    ( clk ),
	.reset  ( ~rst_n ),
	.req    ( rcv_vld ),
	.stall  ( 1'b0 ),
	.vgnt   ( rcv_vgnt ),
	.eval   ( new_event_available ),
	.egnt   ( rcv_egnt )
);

rrarb  send_rrarb (	// Dispatch new events to the cores
	.clk    ( clk ),
	.reset  ( ~rst_n ),
	.req    ( send_vld ),
	.stall  ( 1'b0 ),
	.vgnt   ( send_vgnt ),
	.eval   ( core_available ),
	.egnt   ( send_egnt )
);

rrarb  mem_rrarb (	// Memory access arbiter
	.clk    ( clk ),
	.reset  ( ~rst_n ),
	.req    ( mem_req ),
	.stall  ( mem_req[mem_egnt] && mem_vgnt[mem_egnt] ),
	.vgnt   ( mem_vgnt ),
	.eval   ( mem_req_vld ),
	.egnt   ( mem_egnt )
);

wire [7:0] random_in;
wire [TIME_WID-1:0] event_time;
wire [2:0] event_id;
assign event_time = send_event_data[TIME_WID-1:0];
assign event_id = send_event_data[TIME_WID +: 3];

wire [3:0] p_mc_rq_vld;
wire [2:0] p_mc_rq_cmd[3:0];
wire [3:0] p_mc_rq_scmd[3:0];
wire [47:0] p_mc_rq_vadr[3:0];
wire [1:0] p_mc_rq_size[3:0];
wire [MC_RTNCTL_WIDTH-1:0] p_mc_rq_rtnctl[3:0];
wire [63:0] p_mc_rq_data[3:0];
wire [3:0] p_mc_rq_flush;
wire [3:0] p_mc_rs_stall;

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

// Phold Core instantiation
genvar g;
generate
for (g = 0; g < 4; g = g+1) begin : gen_phold_core
	wire event_valid, new_event_ready, ack, ready;
	wire [2:0] new_event_target;
	wire [TIME_WID-1:0] new_event_time;

	phold_core
	 #(.NUM_MEM_BYTE    ( NUM_MEM_BYTE ), 
	   .MC_RTNCTL_WIDTH ( MC_RTNCTL_WIDTH )
	)  phold_core_inst
	 (
	   .clk              ( clk ),
	   .rst_n            ( rst_n ),
	   .core_id          ( g ),
	   .event_valid      ( event_valid ),
	   .event_id         ( event_id ),
	   .event_time       ( event_time ),
	   .global_time      ( gvt ),
	   .random_in        ( random_in ),
	   .new_event_time   ( new_event_time ),
	   .new_event_target ( new_event_target ),
	   .new_event_ready  ( new_event_ready ),
	   .ready            ( ready ),
	   .ack              ( ack ),
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
	
	assign event_valid = send_event_valid & send_vgnt[g];
	assign new_event_data[g] = {new_event_target, new_event_time};
	assign rcv_vld[g] = new_event_ready;	
	assign ack = rcv_vgnt[g];	
	assign send_vld[g] = ready;
end
endgenerate

// Event queue instantiation
prio_q #(.CMP_WID(TIME_WID)) queue(
	.clk(clk),
	.rst_n(rst_n),
	.enq(enq),
	.deq( deq ),
	.inp_data(new_event),
	.out_data(queue_out),
   .full(),
   .empty(),
	.elem_cnt(event_count)
);

// PRNG instantiation
wire [15:0] seed = 16'hffff; // Initialize PRNG with a seed
LFSR prng (
   .clk   ( clk ),
   .rst_n ( rst_n ),
   .next  ( next_rnd ),
   .seed  ( seed ),
   .rnd   ( random_in )
);

/*
 *	GVT calculation
 */
 reg [TIME_WID*NUM_CORE-1:0] core_times;
 reg [3:0] core_vld;
 wire [TIME_WID-1:0] c_gvt;

 always @(posedge clk or negedge rst_n) begin
	if(~rst_n) begin : reset_core_time_reg
      integer i;
		gvt <= 0;
		core_vld <= 0;
		for(i = 0; i < NUM_CORE; i = i + 1) core_times <= 0;
	end
	else begin
		if(deq) begin
			core_times[TIME_WID*send_egnt +: TIME_WID] <= event_time;
			core_vld[send_egnt] <= 1;
		end
		else if(enq) begin
			core_vld[rcv_vld] <= 0;
		end
		gvt <= (r_state == RUNNING) ? c_gvt : gvt;
	end
 end
 
gvt_monitor #(
   .NUM_CORE(NUM_CORE),
   .TIME_WID(TIME_WID)
) u_gvtmonitor (
   .core_times(core_times),
   .core_vld  (core_vld  ),
   .next_event(queue_out[0 +: TIME_WID] ),
   .gvt       (c_gvt     )
);
 
endmodule
