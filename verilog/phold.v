`include "global_params.vh"

module phold(clk, rst_n, gvt, rtn_vld);
input clk;
input rst_n;
output reg [`TW-1:0] gvt;
output reg rtn_vld;

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
		if(gvt > `SIM_END_TIME) begin
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
wire [`DW-1:0] queue_out;
wire  [`DW-1:0] new_event;
wire [4:0]	event_count;

wire new_event_available, core_available;
wire [1:0] rcv_egnt, send_egnt;
wire [3:0] rcv_vgnt, send_vgnt, rcv_vld, send_vld;
wire [`DW-1:0] new_event_data[3:0];
wire  [`DW-1:0] send_event_data;

assign enq = (r_state == INIT) | 
				((r_state == RUNNING) ? new_event_available : 1'b0) ;
assign deq = (r_state == RUNNING) ? (~new_event_available & core_available) : 0;
assign new_event = (r_state == INIT) ? {init_counter, {`TW{1'b0}} }:
						new_event_data[rcv_egnt];
						

// Debug displays						
always @(posedge clk) begin
	if (deq) $display("GVT: %d, \tEvent sent to CORE %d,\ttime: %d, LP: %d",
						gvt, send_egnt, event_time, event_id);
	if (enq) $display("GVT: %d, \t\t\t\t\t\tNew event from CORE %d,\ttime: %d, LP: %d",
						gvt, rcv_egnt, new_event[`TW-1:0], new_event[`TW +: 3]);
end


/*
 *	Submodule instantiations
 */
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

wire [7:0] random_in;
wire [`TW-1:0] event_time;
wire [2:0] event_id;
assign event_time = send_event_data[`TW-1:0];
assign event_id = send_event_data[`TW +: 3];

// Phold Core instantiation
genvar g;
generate
for (g = 0; g < 4; g = g+1) begin : gen_phold_core
	wire event_valid, new_event_ready, ack, ready;
	wire [2:0] new_event_target;
	wire [`TW-1:0] new_event_time;

	phold_core inst_phold_core (
	   .clk              ( clk ),
	   .rst_n            ( rst_n ),
	   .event_valid      ( event_valid ),
	   .event_id         ( event_id ),
	   .event_time       ( event_time ),
	   .global_time      ( gvt ),
	   .random_in        ( random_in ),
	   .new_event_time   ( new_event_time ),
	   .new_event_target ( new_event_target ),
	   .new_event_ready  ( new_event_ready ),
	   .ack              ( ack ),
	   .ready            ( ready )
	);
	
	assign event_valid = send_event_valid & send_vgnt[g];
	assign new_event_data[g] = {new_event_target, new_event_time};
	assign rcv_vld[g] = new_event_ready;	
	assign ack = rcv_vgnt[g];	
	assign send_vld[g] = ready;
end
endgenerate

// Event queue instantiation
prio_q #(.CW(`TW)) queue(
	.CLK(clk),
	.rst_n(rst_n),
	.enq(enq),
	.deq( deq ),
	.inp_data(new_event),
	.out_data(queue_out),
	.count(event_count)
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
 reg [`TW-1:0] loc_times[3:0];
 reg [3:0] core_act;
 wire [`TW-1:0] t_gvt;
 integer l_t_i;

 always @(posedge clk or negedge rst_n) begin
	if(~rst_n) begin
		gvt <= 0;
		core_act <= 0;
		for(l_t_i = 0; l_t_i <4; l_t_i = l_t_i + 1) loc_times[l_t_i] <= 0;
	end
	else begin
		if(deq) begin
			loc_times[send_egnt] <= event_time;
			core_act[send_egnt] <= 1;
		end
		else if(enq) begin
			core_act[rcv_vld] <= 0;
		end
		gvt <= (r_state == RUNNING) ? t_gvt : gvt;
	end
end
assign t_gvt = minima( minima({core_act[0], loc_times[0]} , {core_act[1], loc_times[1]}),
							minima({core_act[2], loc_times[2]} , {core_act[3], loc_times[3]})
						);

function [`TW-1:0] minima;
input [`TW-1:0] i0, i1;
begin
	minima = i0 < i1 ? i0 : i1;
end
endfunction

endmodule
