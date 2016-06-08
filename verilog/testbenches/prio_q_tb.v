`timescale 1ns / 1ps

`define DWIDTH 14 // MSB of DATA BUS
`define HDEPTH 5	// Depth of heap

module prio_q_tb( );

	reg clk, rst, enq, deq;
    reg [`DWIDTH-1:0] inp_data;
    wire [`DWIDTH-1:0] out_data;
    wire [`HDEPTH-1:0] count;
	
	reg [`DWIDTH-1:0] min;
	
	always @ (posedge clk) begin
		// if (deq) min <= out_data;
		// else min <= 'x;
		if (deq) begin
			min = out_data;
			$write ("%d\n", min);
		end
	end
	
	prio_q DUT (
		.CLK(clk),
		.rst_n(rst),
		.enq (enq),
		.deq (deq),
		.inp_data(inp_data),
		.out_data(out_data),
		.count(count)
	);
	
	
	initial begin
		clk = 1'b0;
		rst = 1'b1;
		#5
		rst = 1'b0;
		#10
		rst = 1'b1;
		
		
	end
	
	always
		#5 clk = !clk;
	
	initial begin
		inp_data = 'd0;
		enq = 'b0;
		deq = 'b0;
		#20
		
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd12;

@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd6;

@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd97;
	
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd33;

@(negedge clk)
	enq = 0;
	deq = 1;

@(negedge clk)
	enq = 0;
	deq = 1;

@(negedge clk)
	enq = 0;
	deq = 1;

@(negedge clk)
	enq = 0;
	deq = 1;

@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd51;

@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd33;
	
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd38;
	
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd21;

@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;

@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd25;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd26;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd28;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd27;

@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;

@(negedge clk)
	enq = 0;
	deq = 0;
						
	end
	
endmodule