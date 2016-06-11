module phold_core
	#(
	parameter NIDB = 3, // Number of bits in ID. Number of Available LP < 2 ^ NIDB
	parameter NRB = 8	// Number of bits in Random number generator
	)(
	input clk,
	input rst_n,
	
	// Incoming events
	input event_valid,
	input [NIDB-1:0] event_id,
	input [15:0] event_time,
	
	input [15:0] global_time,
	
	// Receive a random number
	input [NRB-1:0] random_in,
	
	// New generated event
	output reg [15:0] new_event_time,
	output reg [NIDB-1:0] new_event_target,
	output reg new_event_ready
);
	
	reg [NRB-1:0] rnd;
	reg [15:0] local_time, gvt;
	reg [NIDB-1:0] local_id;
	
	always@(posedge clk) begin
		if(event_valid) begin
			local_time <= event_time;
			local_id <= event_id;
			gvt <= global_time;
			rnd <= random_in;
		end
	end

	localparam 	IDLE = 1'd0,
				WORKING = 1'd1;
				
	reg c_state, r_state;
	wire finished;
	
	always@* begin
		c_state = r_state;
		case(r_state)
		IDLE : begin
			if(event_valid)
				c_state = WORKING;
		end
		WORKING: begin
			if (finished)
				c_state = IDLE;
		end
		endcase
	end
	
	
	reg [2:0] counter;
	always@(posedge clk or negedge rst_n) begin
		r_state <= (rst_n) ? c_state : 1'b0;
		counter <= (rst_n) ? 
						(r_state == WORKING ? counter + 1 : 3'b0) : 3'b0; 
		
		new_event_ready <= rst_n ? finished : 0;
		new_event_time <= local_time + 10 + rnd [4:0]; // Keep at least 10 units time gap between events
		new_event_target <= rnd[NRB-1:5];
	end
	
	assign finished = (counter == rnd[2:0]); // Simulate a random processing delay
	
endmodule