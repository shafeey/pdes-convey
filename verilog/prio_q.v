`timescale 1ns / 1ps

`define DW 16 // Width of data bus
`define HD 5 // Depth of heap, heap size = (2^HD)-1


module prio_q(
    input CLK,
    input enq,
    input deq,
    input [`DW-1:0] inp_data,
    output [`DW-1:0] out_data,
    input rst_n,
    output reg [`HD-1:0] count
    );
	parameter CW = `DW; // Compare upto CW bits,
	
	reg	[`DW-1:0] 	L0, L1[1:0], L2[3:0], L3[7:0]; // Heap levels
	
	reg [`DW-1:0]	tmp1, tmp2, tmp3; // Buffer contains data in-between levels
	reg	prop_next1, prop_next2, prop_next3; // Propagate signals
	reg [`HD-1:0]	path12, path34; // Path of propagation
	
	assign out_data = L0;
	parameter LOGB2_HD = $clog2(`HD);
		
	wire [`HD-1:0] target;
	assign target = count + `HD'b1;

	wire [LOGB2_HD:0]  dest_level;
	reg [LOGB2_HD:0] dest_level_old;	
	assign dest_level = clogb2(count);
	
	always @ (posedge CLK or negedge rst_n) begin // Element count
		if(!rst_n) begin
			count <= 0;
		end
		else begin
			if(enq)
				count <= count + 1;
			else if(deq)
				count <= count -1;
			else
				count <= count;
		end
	end
	
	always @ (posedge CLK or negedge rst_n) begin // propagation paths
		if(!rst_n) begin
			path12 <= 'b0;
			path34 <= 'b0;
		end
		else begin
			if (target > 15)
				path12 <= (target - `HD'd16)<<1;
			else if (target > 7)
				path12 <= (target - `HD'd8)<<2;
			else if (target > 3)
				path12 <= (target - `HD'd4)<<3;
			else if (count > 1)
				path12 <= (target - `HD'd2)<<4;
			else 
				path12 <= 'b0;
				
			path34 <= path12;
		end
	end
	
	wire [`HD-1:0] index1, index2, index3;
	reg del_next1, del_next2, del_next3;
	wire [`HD-1:0] del_index1;
	reg del_path1;
	reg [1:0] del_path2;
	reg [2:0] del_path3;
	wire [`HD-1:0] del_index2;
	
	always @ (posedge CLK or negedge rst_n) begin // Root level
		if(!rst_n) begin
			L0 <= 0;
			prop_next1 <= 0;
		end
		else begin
			if(enq) begin
				if(target == 'b1) begin
					L0 <= inp_data;
					prop_next1 <= 0;
				end
				else begin
					prop_next1 <= 1;
					if(inp_data[CW-1:0] < L0[CW-1:0]) begin
						tmp1 <= L0;
						L0 <= inp_data;
					end
					else tmp1 <= inp_data;
				end
				del_next1 <= 0;
			end
			else if(deq) begin
				if(count > 'h2) begin
					tmp1 <= (prop_next2) ? tmp2 :
								(count > 7) ? L3[count - 8] :
									(count > 3) ? 
										((count == del_index2) ? tmp2 : L2[count - 4]) : 
											L1[1];
					if(L1[0][CW-1:0] < L1[1][CW-1:0]) begin
						L0 <= L1[0];
						del_path1 <= 'b0;
					end
					else begin
						L0 <= L1[1];
						del_path1 <= 'b1;
					end
					del_next1 <= 1;
				end
				else begin
					L0 <= L1[0];
					del_next1 <= 0;
					tmp1 <= 0; //
				end
				prop_next1 <= 0;
			end
			else begin
				prop_next1 <= 0;
				del_next1 <= 0;
				tmp1 <= 0; //
			end
		end
	end
	
	assign index1 = path12[`HD-1]; // get node index to operate on
	assign del_index1 = {1'b1, del_path1};
		
	reg [`DW-1:0] c_tmp2, c_tmp3;
	reg c_del_next2, c_del_next3, c_del_child_id2, c_del_child_id3; 
	reg [`DW-1:0] e_tmp2, e_tmp3, e_tmp4;
	reg e_prop_next2, e_prop_next3, e_prop_next4;
	reg [`DW-1:0] c_L1, c_L2, e_L1, e_L2, e_L3;
	
	always @* begin : comb // Combinational logic between levels
		delete_comb( 	del_index1, count,
							L2[del_path1*2], L2[del_path1*2+1],
							tmp1, c_tmp2,
							c_L1,
							c_del_next2, c_del_child_id2
		);
		insert_comb(	(dest_level == 'h1), L1[index1], tmp1,
						e_tmp2, e_L1, e_prop_next2
		);
	end
	
	always @ (negedge CLK or negedge rst_n) begin // Level 1
		if(!rst_n) begin : reset_L1
			integer i;
			for (i = 0; i < 2; i = i+1)	L1[i] <= 0;
			prop_next2 <= 0;
			del_path2 <= 0;
		end
		else begin
			if (prop_next1) begin // New data descending from upper level
				tmp2 <= e_tmp2;
				L1[index1] <= e_L1;
				prop_next2 <= e_prop_next2;
				
				del_next2 <= 0;
			end
			else if (del_next1 == 1) begin
				L1[del_path1] <= c_L1;
				tmp2 <= c_tmp2;
				del_next2 <= c_del_next2;
				del_path2 <= {del_path1, c_del_child_id2};
				
				prop_next2 <= 0;
			end
			else begin
				prop_next2 <= 0;
				del_next2 <= 0;
			end
		end
	end
		
	assign index2 = path12[`HD-1:`HD-2]; // get node index to operate on
	assign del_index2 = {del_next2, del_path2};
	wire [`HD-1:0] count_del = count - deq;
	
	always @* begin
		delete_comb(	del_index2, count_del,
							L3[del_path2*2], L3[del_path2*2+1],
							tmp2, c_tmp3,
							c_L2,
							c_del_next3, c_del_child_id3
		);
		insert_comb(	(dest_level == 'h2), L2[index2], tmp2,
						e_tmp3, e_L2, e_prop_next3
		);
	end
	
	always @ (posedge CLK or negedge rst_n) begin // Level 2
		if(!rst_n) begin : reset_L2
			integer i;
			for (i = 0; i < 4; i = i+1)	L2[i] <= 0;
			prop_next3 <= 0;
		end
		else begin
			if (prop_next2 && !deq) begin 	 
			/* 	New data descending from upper level and deque isn't issued for this clock cycle.
				A deque would take the propagating data and place it at the root so that it can
				propagate down again for a deque phase. */	
				tmp3 <= e_tmp3;
				L2[index2] <= e_L2;
				prop_next3 <= e_prop_next3;
				
				del_next3 <= 0;
			end
			else if (del_next2 == 1) begin
				L2[del_path2] <= c_L2;
				tmp3 <= c_tmp3;
				del_next3 <= c_del_next3;
				del_path3 <= {del_path2, c_del_child_id3};				
				
				prop_next3 <= 0;
			end
			else begin
				prop_next3 <= 0;
				del_next3 <= 0;
				tmp3 <= 0; //
			end
		end
	end
	
	
	always @ (posedge CLK) begin
		dest_level_old <= dest_level;
	end
	
	assign index3 = path34[`HD-1:`HD-3]; // get node index to operate on
	assign del_index3 = {1'b1, del_path3};
	
	always @* begin
		insert_comb(	(dest_level_old == 'h3), L3[index3], tmp3,
						e_tmp4, e_L3, e_prop_next4
		);
	end
	
	always @ (negedge CLK or negedge rst_n) begin // Level 3
		if(!rst_n) begin : reset_L3
			integer i;
			for (i = 0; i < 8; i = i+1)	L3[i] <= 0;
		end
		else begin
			if (prop_next3) begin // New data descending from upper level
				L3[index3] <= e_L3;
			end
			else if (del_next3 == 1) begin
				L3[del_path3] <= tmp3;
			end
		end
	end
	
	task automatic insert_comb;

		input target_level;	// True if this is the destination level
		input [`DW-1:0]	node_cur; // Current data of the node
		input [`DW-1:0] from_top;	// Temporary buffer from level above

		output reg [`DW-1:0] to_bot;// Temporary buffer for level below
		output reg [`DW-1:0] node;	// Next data for the node
		output reg prop_next;	 	// Pass insert signal to next level

		begin
			prop_next = 0;
			node = node_cur;
			
			if(target_level) begin	// Reached target level
				node = from_top;
			end
			else begin 	// Compare and pass larger value to next level
				prop_next = 1;
				if (from_top[CW-1:0] < node[CW-1:0]) begin
					to_bot = node;
					node = from_top;
				end
				else to_bot = from_top;
			end
		end

	endtask
	
	task automatic delete_comb;
		input [`HD-1:0] del_index;	// Index of the node
		input [`HD-1:0] count;
		input [`DW-1:0]	child0, child1;
		input [`DW-1:0] from_top;	// Temporary buffer from level above

		output reg [`DW-1:0] to_bot;// Temporary buffer for level below
		output reg [`DW-1:0]	node;
		output reg del_next;	 	// Pass delete signal to next level
		output reg del_child_id; 	// Child id to be deleted

		begin
			node = from_top;
			del_next = 0;
			to_bot = 0;
			del_path2 = del_path2;
			
			if( del_index*2 + 1 <= count ) begin
				if( child0[CW-1:0] < child1[CW-1:0] ) begin
					if( child0[CW-1:0] < from_top[CW-1:0] ) begin
						node = child0;
						del_next = 1;
						to_bot = from_top;
						del_child_id = 0;
					end
				end
				else begin
					if( child1[CW-1:0] < from_top[CW-1:0] ) begin
						node = child1;
						del_next = 1;
						to_bot = from_top;
						del_child_id = 1;
					end
				end
			end
			else if( del_index*2 <= count ) begin
				if( child0[CW-1:0] < from_top[CW-1:0] ) begin
					node = child0;
					del_next = 1;
					to_bot = from_top;
					del_child_id = 0;
				end
			end
		end
	endtask
	
	function integer clogb2;
		input [`HD-1:0] value;
		integer 	i;
		begin
			clogb2 = 0;
			for(i = 0; 2**i <= value; i = i + 1)
				clogb2 = i;
		end
	endfunction
		
endmodule
