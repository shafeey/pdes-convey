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
	
	//reg [`HD:0] count;
	
	reg	[`DW-1:0] 	L0;
	reg [`DW-1:0]	L1[1:0];
	reg	[`DW-1:0]	L2[3:0];
	reg	[`DW-1:0]	L3[7:0];
	reg	[`DW-1:0]	L4[15:0];
	
	reg [`DW-1:0]	tmp1, tmp2, tmp3, tmp4, tmp5; //, tmp3, tmp4;
	reg			prop_data1, prop_data2, prop_data3, prop_data4, prop_data5; //, pendingData3, pendingData4;
	reg [`HD-1:0]	path12, path34; //, path23;
	
	assign out_data = L0;
	
	parameter LOGB2_HD = $clog2(`HD);
		
	wire [`HD-1:0] target;
	wire [LOGB2_HD:0]  dest_level;
	reg [LOGB2_HD:0] dest_level_old;
	
	assign target = count + `HD'b1;
	
	// assign dest_level = clogb2(target);
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
	
	reg del_next1;
	reg del_path1;
	
		wire [`HD-1:0] del_index2;

	
	always @ (posedge CLK or negedge rst_n) begin // Root level
		if(!rst_n) begin
			L0 <= 0;
			prop_data1 <= 0;
		end
		else begin
			if(enq) begin
				if(target == 'b1) begin
					L0 <= inp_data;
					prop_data1 <= 0;
				end
				else begin
					prop_data1 <= 1;
					if(inp_data < L0) begin
						tmp1 <= L0;
						L0 <= inp_data;
					end
					else tmp1 <= inp_data;
				end
				del_next1 <= 0;
			end
			else if(deq) begin
				if(count > 'h2) begin
					tmp1 <= (prop_data2) ? tmp2 :
								(count > 7) ? L3[count - 8] :
									(count > 3) ? 
										((count == del_index2) ? tmp2 : L2[count - 4]) : 
											L1[1];
					if(L1[0] < L1[1]) begin
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
				prop_data1 <= 0;
			end
			else begin
				prop_data1 <= 0;
				del_next1 <= 0;
				tmp1 <= 0; //
			end
		end
	end
	
	
	wire [`HD-1:0] index1;
	assign index1 = path12[`HD-1]; // get node index to operate on
	wire [`HD-1:0] del_index1;
	assign del_index1 = {1'b1, del_path1};
	reg del_next2;
	reg [1:0] del_path2;
	
	always @ (negedge CLK or negedge rst_n) begin // Level 1
		if(!rst_n) begin : reset_L1
			integer i;
			for (i = 0; i < 2; i = i+1)	L1[i] <= 0;
			prop_data2 <= 0;
			del_path2 <= 0;
		end
		else begin
			if (prop_data1) begin // New data descending from upper level
				if(dest_level == 'h1) begin	// Won't propagate to next level
					prop_data2 <= 0;	
					L1[index1] <= tmp1;
				end
				else begin	// Compare and pass larger value to next level
					prop_data2 <= 1;
					if(tmp1 < L1[index1]) begin
						tmp2 <= L1[index1];
						L1[index1] <= tmp1;
					end
					else tmp2 <= tmp1;
				end
				del_next2 <= 0;
			end
			else if (del_next1 == 1) begin
				if ( del_index1*2 + 1 <= count) begin
					if( L2[del_path1*2] < L2 [del_path1*2 + 1]) begin
						if (L2[del_path1*2] < tmp1) begin
							L1[del_path1] <= L2[del_path1*2];
							del_path2 <= {del_path1, 1'b0};
							del_next2 <= 1;
							tmp2 <= tmp1;
						end
						else begin
							L1[del_path1] <= tmp1;
							del_next2 <= 0;
							tmp2 <= 0; //
						end
					end
					else begin
						if (L2[del_path1*2 + 1] < tmp1) begin
							L1[del_path1] <= L2[del_path1*2 + 1];
							del_path2 <= {del_path1, 1'b1};
							del_next2 <= 1;
							tmp2 <= tmp1;
						end
						else begin
							L1[del_path1] <= tmp1;
							del_next2 <= 0;
							tmp2 <= 0; //
						end
					end
				end
				else if ( del_index1*2 <= count) begin
					if (L2[del_path1*2] < tmp1) begin
						L1[del_path1] <= L2[del_path1*2];
						del_path2 <= {del_path1, 1'b0};
						del_next2 <= 1;
						tmp2 <= tmp1;
					end
					else begin
						L1[del_path1] <= tmp1;
						del_next2 <= 0;
						tmp2 <= 0; // 
					end
				end
				else begin
					L1[del_path1] <= tmp1;
					del_next2 <= 0;
					tmp2 <= 0; //
				end
				prop_data2 <= 0;
			end
			else begin
				prop_data2 <= 0;
				del_next2 <= 0;
				tmp2 <= 0; //
			end
		end
	end
	
	
	wire [`HD-1:0] index2;
	assign index2 = path12[`HD-1:`HD-2]; // get node index to operate on
	assign del_index2 = {del_next2, del_path2};
	reg del_next3;
	reg [2:0] del_path3;
	wire [`HD-1:0] count_del;
	assign count_del = count + !{deq};
	
	always @ (posedge CLK or negedge rst_n) begin // Level 2
		if(!rst_n) begin : reset_L2
			integer i;
			for (i = 0; i < 4; i = i+1)	L2[i] <= 0;
			prop_data3 <= 0;
		end
		else begin
			if (prop_data2 && !deq) begin 	 
			/* 	New data descending from upper level and deque isn't issued for this clock cycle.
				A deque would take the propagating data and place it at the root so that it can
				propagate down again for a deque phase. */	
				if(dest_level == 'h2) begin	// Won't propagate to next level
					prop_data3 <= 0;	
					L2[index2] <= tmp2;
				end
				else begin	// Compare and pass larger value to next level
					prop_data3 <= 1;
					if(tmp2 < L2[index2]) begin
						tmp3 <= L2[index2];
						L2[index2] <= tmp2;
					end
					else tmp3 <= tmp2;
				end
			end
			else if (del_next2 == 1) begin
				if ( del_index2*2 + 1 < count_del) begin
					if( L3[del_path2*2] < L3 [del_path2*2 + 1]) begin
						if (L3[del_path2*2] < tmp2) begin
							L2[del_path2] <= L3[del_path2*2];
							del_path3 <= {del_path2, 1'b0};
							del_next3 <= 1;
							tmp3 <= tmp2;
						end
						else begin
							L2[del_path2] <= tmp2;
							del_next3 <= 0;
							tmp3 <= 0; //
						end
					end
					else begin
						if (L3[del_path2*2 + 1] < tmp2) begin
							L2[del_path2] <= L3[del_path2*2 + 1];
							del_path3 <= {del_path2, 1'b1};
							del_next3 <= 1;
							tmp3 <= tmp2;
						end
						else begin
							L2[del_path2] <= tmp2;
							del_next3 <= 0;
							tmp3 <= 0; //
						end
					end
				end
				else if ( del_index2*2 < count_del) begin
					if (L3[del_path2*2] < tmp2) begin
						L2[del_path2] <= L3[del_path2*2];
						del_path3 <= {del_path2, 1'b0};
						del_next3 <= 1;
						tmp3 <= tmp2;
					end
					else begin
						L2[del_path2] <= tmp2;
						del_next3 <= 0;
						tmp3 <= 0; // 
					end
				end
				else begin
					L2[del_path2] <= tmp2;
					del_next3 <= 0;
					tmp3 <= 0; //
				end
				prop_data3 <= 0;
			end
			else begin
				prop_data3 <= 0;
				del_next3 <= 0;
				tmp3 <= 0; //
			end
		end
	end
	
	
	always @ (posedge CLK) begin
		dest_level_old <= dest_level;
	end
	
	wire [`HD-1:0] index3;
	assign index3 = path34[`HD-1:`HD-3]; // get node index to operate on
	
	assign del_index3 = {1'b1, del_path3};
	reg [3:0] del_path4;
	
	always @ (negedge CLK or negedge rst_n) begin // Level 3
		if(!rst_n) begin : reset_L3
			integer i;
			for (i = 0; i < 8; i = i+1)	L3[i] <= 0;
			prop_data4 <= 0;
		end
		else begin
			if (prop_data3) begin // New data descending from upper level
				
				if(dest_level_old == 'h3) begin	// Won't propagate to next level
					prop_data4 <= 0;	
					L3[index3] <= tmp3;
				end
				else begin	// Compare and pass larger value to next level
					prop_data4 <= 1;
					if(tmp3 < L3[index3]) begin
						tmp4 <= L3[index3];
						L3[index3] <= tmp3;
					end
					else tmp4 <= tmp3;
				end
			end
			else if (del_next3 == 1) begin
				L3[del_path3] <= tmp3;
				prop_data4 <= 0;
			end
			else begin
				prop_data4 <= 0;
			end
		end
	end
	
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
