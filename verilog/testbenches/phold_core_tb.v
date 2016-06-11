module phold_core_tb;

// Parameter/Signal Declarations
parameter NIDB  = 3;
parameter NRB   = 8;
reg clk;
reg rst_n;
reg event_valid;
reg [NIDB-1:0] event_id;
reg [15:0] event_time;
reg [15:0] global_time;
reg [NRB-1:0] random_in;
wire [15:0] new_event_time;
wire [NIDB-1:0] new_event_target;
wire new_event_ready;


initial begin
	clk = 0;
	forever #5 clk = ~clk;
end

initial begin
	random_in = $random;
	forever @(negedge event_valid) random_in = $random;
end

initial begin
	rst_n = 1;
	event_valid = 0;
	global_time = 0;
	event_id = 0;
	event_time = 0;
	
	#10 rst_n = 0;
	#20 rst_n = 1;
	
	#10
	@(negedge clk)
	event_id = 2;
	event_time = 5;
	event_valid = 1;
	
	@(posedge clk)
	event_valid = 0;
	
	@(posedge new_event_ready)
	event_id = 4;
	event_time = 10;
	event_valid = 1;
	
	@(posedge clk)
	event_valid = 0;
	
	@(posedge new_event_ready)
	event_id = 0;
	event_time = 15;
	event_valid = 1;
	
	@(posedge clk)
	event_valid = 0;
end



// Instance Declarations
phold_core
 #(
   .NIDB ( NIDB ),
   .NRB  ( NRB )
)  inst_phold_core
 (
   .clk              ( clk ),
   .rst_n            ( rst_n ),
   .event_valid      ( event_valid ),
   .event_id         ( event_id ),
   .event_time       ( event_time ),
   .global_time      ( global_time ),
   .random_in        ( random_in ),
   .new_event_time   ( new_event_time ),
   .new_event_target ( new_event_target ),
   .new_event_ready  ( new_event_ready )
);
endmodule