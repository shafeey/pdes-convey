`timescale 1ns / 1ps

`define DWIDTH 16 // MSB of DATA BUS
`define HDEPTH 5	// Depth of heap

module prio_q_tb( );

	reg clk, rst, enq, deq;
    reg [`DWIDTH-1:0] inp_data;
    wire [`DWIDTH-1:0] out_data;
    wire [`HDEPTH-1:0] count;
	
	reg done;
	
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

integer f;		
initial begin
	#0;
	f = $fopen("q_ops.txt");
	$monitoron;
	@(posedge done)
	$monitoroff;
	#10;
	$fclose(f);
end

initial begin
	$fmonitor(f, "clk:%d, enq: %d, deq:%d, in:%d, out:%d, count:%d",
					clk, enq, deq, inp_data, out_data, count);
end
	
initial begin
	inp_data = 'd0;
	enq = 'b0;
	deq = 'b0;
	done = 0;
	
	#20
		
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd72;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd44;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd85;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd43;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd71;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd15;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd70;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd91;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd59;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd74;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd68;
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
	enq = 1;
	deq = 0;
	inp_data = 'd36;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd24;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd94;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd37;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd47;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd58;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd29;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd89;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd23;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd86;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd82;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd98;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd93;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd20;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd23;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd65;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd36;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd17;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd73;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd83;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd16;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd60;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd47;
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
	enq = 1;
	deq = 0;
	inp_data = 'd41;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd87;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd60;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd76;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd79;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd98;
@(negedge clk)
	enq = 0;
	deq = 1;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd25;
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
	inp_data = 'd16;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd7;
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
	inp_data = 'd22;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd78;
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
	inp_data = 'd45;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd34;
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
	inp_data = 'd28;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd31;
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
	inp_data = 'd21;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd72;
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
	inp_data = 'd98;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd49;
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
	inp_data = 'd54;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd31;
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
	inp_data = 'd96;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd20;
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
	inp_data = 'd42;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd36;
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
	inp_data = 'd63;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd53;
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
	inp_data = 'd14;
@(negedge clk)
	enq = 1;
	deq = 0;
	inp_data = 'd67;
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
	inp_data = 'd6;
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
@(negedge clk)	
	done = 1;		
end
	
endmodule