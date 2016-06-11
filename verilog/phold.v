module phold(CLK, rst_n, gvt, rtn_vld);
input CLK;
input rst_n;
output reg [13:0] gvt;
output reg rtn_vld;

reg enq, deq;

wire [13:0] rnd1, rnd2;
wire [15:0] queue_in, queue_out;
reg  [15:0] new_event;
wire [4:0]	event_count;



localparam 	IDLE = 2'd0,
			INIT = 2'd1,
			READY = 2'd2,
			RUNNING = 2'd3,
			FINISHED = 2'd4;

reg queue_ready, prng_ready;
reg	[2:0]	c_state, r_state;
reg c_rtn_vld;

always @* begin
	c_state = r_state;
	c_rtn_vld = rtn_vld;
	
	case(r_state)
	IDLE:
		if(rst_n)
			c_state = INIT;
	INIT:
		if(queue_ready && prng_ready) begin
			c_state = READY;
		end
	READY:
		c_state = RUNNING;
	RUNNING:
		if(gvt > 14'd12000) begin
			c_state = FINISHED;
			c_rtn_vld = 1;
		end
	FINISHED: begin
		c_state = IDLE;
		c_rtn_vld = 0;
	end
	endcase
end
	
always @(posedge CLK or negedge rst_n) begin
	if(!rst_n) begin
		r_state <= 3'b0;
		rtn_vld <= 0;
	end
	else begin
		r_state <= c_state;
		rtn_vld <= c_rtn_vld;
	end
end


reg [3:0] counter;
always @(posedge CLK or negedge rst_n) begin
	if(!rst_n) begin
		counter <= 0;
	end
	else begin
		if(r_state == INIT || r_state == RUNNING)
			counter <= counter + 1;
		else
			counter <= 0;		
	end
end

wire [1:0] op = counter[3:2];
wire [1:0] LP_id = counter[1:0];

reg [1:0] id[3:0];
reg [6:0] rnd_LP[3:0];
wire [6:0] rnd[3:0];
wire [15:0] new_event_LP[3:0];
reg [13:0] time_LP[3:0];

assign rnd[0] = rnd1[6:0];
assign rnd[1] = rnd2[6:0];
assign rnd[2] = rnd1[13:8];
assign rnd[3] = rnd2[13:8];

always @(posedge CLK or negedge rst_n) begin : process_LP
	if(!rst_n) begin
		enq <= 0;
		deq <= 0;
		gvt <= 0;
		queue_ready <= 0;
		prng_ready <= 0;
	end
	else begin
		case(r_state)
		INIT: begin
			enq <= !queue_ready;
			new_event <= {14'b0, LP_id};
			queue_ready <= (counter == 3) ? 1 : queue_ready;
			prng_ready <= (counter == 14);
		end
		RUNNING: begin
			case(op)
			2'b00: begin 	// get events from the queue
				id[LP_id] <= queue_out[1:0];
				time_LP[LP_id] <= queue_out[15:2];
				rnd_LP[LP_id] <= rnd[LP_id];
				deq <= 1;
			end
			2'b10: begin // send new events to the queue
				new_event <= new_event_LP[LP_id];
				gvt <= time_LP[counter[1:0]];
				enq <= 1;
				$display("gvt= %d, LP: %d, new event at %d to LP %d",
								time_LP[LP_id], id[LP_id], new_event_LP[LP_id][15:2],
								new_event_LP[LP_id][1:0]);
			end
			default: begin
				enq <= 0;
				deq <= 0;
			end
			endcase
		end
		default: begin
			enq <= 0;
			deq <= 0;
		end
		endcase
	end
end

// Event queue instantiation
prio_q queue(
	.CLK(~CLK),
	.rst_n(rst_n),
	.enq(enq),
	.deq(deq),
	.inp_data(new_event),
	.out_data(queue_out),
	.count(event_count)
);

// PRNG instantiation
LFSR prng1(
    .clock(CLK),
    .reset(!rst_n),
	.seed(14'hffff),
    .rnd(rnd1)
    );
LFSR prng2(
    .clock(CLK),
    .reset(!rst_n),
	.seed(14'hAAAA),
    .rnd(rnd2)
    );


phold_LP LP0 (CLK, rst_n, id[0], rnd_LP[0], time_LP[0], new_event_LP[0]);
phold_LP LP1 (CLK, rst_n, id[1], rnd_LP[1], time_LP[1], new_event_LP[1]);
phold_LP LP2 (CLK, rst_n, id[2], rnd_LP[2], time_LP[2], new_event_LP[2]);
phold_LP LP3 (CLK, rst_n, id[3], rnd_LP[3], time_LP[3], new_event_LP[3]);

endmodule

