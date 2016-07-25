`timescale 1ns / 100ps

module prio_q #(
   parameter WIDTH = 32, // Width of data ports
   parameter CMP_WID = 32, // Only compare CMP_WID LSBs to sort heap
   parameter DEPTH = 5 // Depth of heap, heap size = (2^DEPTH)-1 = 31
)(
   input                clk,
   input                enq,
   input                deq,
   input  [WIDTH-1:0]   inp_data,
   output [WIDTH-1:0]   out_data,
   output [DEPTH-1:0]   elem_cnt,
   input                rst_n
   );
   
	localparam LOG_HD = $clog2(DEPTH);
   
   // Heap element containers
	reg [WIDTH-1:0]  L0, L1[1:0], L2[3:0], L3[7:0], L4[15:0]; // Heap levels
	reg [WIDTH-1:0]  tmp1, tmp2, tmp3, tmp4; // Data incoming to level
   
   // Heap operation signals
	reg              carry1, carry2, carry3, carry4; // Carry element to level
	reg [DEPTH-1:0]  path12, path34; // Path for insertion to levels
	reg              del1, del2, del3, del4; // Delete element from level
	reg              del_path1; // Node to replace/delete from level
	reg [1:0]        del_path2;
	reg [2:0]        del_path3;
	reg [3:0]        del_path4;
   
   
   
	reg [DEPTH-1:0]  count;
	reg  [LOG_HD:0]  dest_level_prev;	
   // Internal wires
   
   // Index of nodes being operated on in each level
	wire [DEPTH-1:0] index1, index2, index3, index4;
	wire [DEPTH-1:0] del_index1, del_index2, del_index3, del_index4;
   
	wire [LOG_HD:0]  dest_level; // Destination for element being inserted
   /*
    * Out put assignments
    */
	assign out_data = L0;
   assign elem_cnt = count;

	assign dest_level = clogb2(count);
   
	always @ (posedge clk) begin // Element count
		if(!rst_n) begin
			count <= 0;
			path12 <= 0;
			path34 <= 0;
		end
      else begin
			if(enq)
				count <= count + 1;
			else if(deq)
				count <= count -1;
			else
				count <= count;
         
			path12 <= find_path(count);
			path34 <= path12;
		end
	end

	assign index1 = path12[DEPTH-1]; // get node index to operate on
	assign del_index1 = {1'b1, del_path1};
		
	reg [WIDTH-1:0] c_tmp1, c_tmp2, c_tmp3, c_tmp4;
	reg c_del1, c_del2, c_del3, c_del4, c_del_child_id1, c_del_child_id2, c_del_child_id3, c_del_child_id4;
	reg [WIDTH-1:0] e_tmp1, e_tmp2, e_tmp3, e_tmp4;
	reg e_prop_next1, e_prop_next2, e_prop_next3, e_prop_next4;
	reg [WIDTH-1:0] c_L0, c_L1, c_L2, c_L3, e_L0, e_L1, e_L2, e_L3;	
   
   always @* begin : comb0 // Combinational logic between levels
		insert_comb(	(count == 'h0), L0, inp_data,
						e_tmp1, e_L0, e_prop_next1
         );
      
      c_tmp1 = 0;
      c_L0 = L1[0];
      c_del1 = 0;
      c_del_child_id1 = 0;
      
      if(carry2)
         c_tmp1 = tmp2;
      else if(carry4 || (count == del_index4 && del4))
         c_tmp1 = tmp4;
      else if(count > 15) 
         c_tmp1 =  L4[count - 16];
      else if(count >7)
         c_tmp1 = L3[count - 8];
      else if(count > 3)
         c_tmp1 = (count == del_index2) ? tmp2 : L2[count - 4];
      else
         c_tmp1 = L1[1];
         
      if(count > 'h2) begin
			if(L1[0][CMP_WID-1:0] >= L1[1][CMP_WID-1:0]) begin
				c_L0 = L1[1];
				c_del_child_id1 = 1'b1;
			end
			c_del1 = 1;
		end
   end
   
	always @ (posedge clk or negedge rst_n) begin // Root level
		if(!rst_n) begin
			L0 <= 0;
			carry1 <= 0;
		end
      else begin
         carry1 <= enq ? e_prop_next1 : 0;
         del1 <= deq ? c_del1 : 0;
			if(enq) begin
            L0 <= e_L0;
            tmp1 <= e_tmp1;
			end
         else if(deq) begin
            tmp1 <= c_tmp1;
            L0 <= c_L0;
            del_path1 <= c_del_child_id1;
			end
		end
   end
      
	always @* begin : comb // Combinational logic between levels
		delete_comb( 	del_index1, count,
							L2[del_path1*2], L2[del_path1*2+1],
							tmp1, c_tmp2,
							c_L1,
							c_del2, c_del_child_id2
		);
		insert_comb(	(dest_level == 'h1), L1[index1], tmp1,
						e_tmp2, e_L1, e_prop_next2
		);
	end
	
	always @ (negedge clk or negedge rst_n) begin // Level 1
		if(!rst_n) begin : reset_L1
			integer i;
			for (i = 0; i < 2; i = i+1)	L1[i] <= 0;
			carry2 <= 0;
			del_path2 <= 0;
		end
		else begin
			if (carry1) begin // New data descending from upper level
				tmp2 <= e_tmp2;
				L1[index1] <= e_L1;
				carry2 <= e_prop_next2;
				
				del2 <= 0;
			end
			else if (del1 == 1) begin
				L1[del_path1] <= c_L1;
				tmp2 <= c_tmp2;
				del2 <= c_del2;
				del_path2 <= {del_path1, c_del_child_id2};
				
				carry2 <= 0;
			end
			else begin
				carry2 <= 0;
				del2 <= 0;
            tmp2<= 0;
			end
		end
	end
		
	assign index2 = path12[DEPTH-1:DEPTH-2]; // get node index to operate on
	assign del_index2 = {del2, del_path2};
	wire [DEPTH-1:0] count_del = count - deq;
	
	always @* begin
		delete_comb(	del_index2, count_del,
							L3[del_path2*2], L3[del_path2*2+1],
							tmp2, c_tmp3,
							c_L2,
							c_del3, c_del_child_id3
		);
		insert_comb(	(dest_level == 'h2), L2[index2], tmp2,
						e_tmp3, e_L2, e_prop_next3
		);
	end
	
	always @ (posedge clk or negedge rst_n) begin // Level 2
		if(!rst_n) begin : reset_L2
			integer i;
			for (i = 0; i < 4; i = i+1)	L2[i] <= 0;
			carry3 <= 0;
		end
		else begin
			if (carry2 && !deq) begin 	 
			/* 	New data descending from upper level and dequeue isn't issued for this clock cycle.
				A dequeue would take the propagating data and place it at the root so that it can
				propagate down again for a dequeue phase. */	
				tmp3 <= e_tmp3;
				L2[index2] <= e_L2;
				carry3 <= e_prop_next3;
				
				del3 <= 0;
			end
			else if (del2 == 1) begin
				L2[del_path2] <= c_L2;
				tmp3 <= c_tmp3;
				del3 <= c_del3;
				del_path3 <= {del_path2, c_del_child_id3};				
				
				carry3 <= 0;
			end
			else begin
				carry3 <= 0;
				del3 <= 0;
				tmp3 <= 0; //
			end
		end
	end
	
   reg last_enq;
	always @ (posedge clk) begin
		dest_level_prev <= dest_level;
      last_enq <= (rst_n) ? enq : 0;
	end
	
	assign index3 = path34[DEPTH-1:DEPTH-3]; // get node index to operate on
	assign del_index3 = {1'b1, del_path3};
	
	always @* begin
		delete_comb(	del_index3, count - (last_enq ),
							L4[del_path3*2], L4[del_path3*2+1],
							tmp3, c_tmp4,
							c_L3,
							c_del4, c_del_child_id4
		);
		insert_comb(	(dest_level_prev == 'h3), L3[index3], tmp3,
						e_tmp4, e_L3, e_prop_next4
		);
	end
	
	always @ (negedge clk or negedge rst_n) begin // Level 3
		if(!rst_n) begin : reset_L3
			integer i;
			for (i = 0; i < 8; i = i+1)	L3[i] <= 0;
		end
		else begin
			if (carry3) begin // New data descending from upper level
            tmp4 <= e_tmp4;
				L3[index3] <= e_L3;
            carry4 <= e_prop_next4;
            
            del4 <= 0;
			end
			else if (del3 == 1) begin
				L3[del_path3] <= c_L3;
            tmp4 <= c_tmp4;
            del4 <= c_del4;
            del_path4 <= {del_path3, c_del_child_id4};
            
            carry4 <= 0;
         end
         else begin
            carry4 <= 0;
            del4 <= 0;
            tmp4 <= 0;
         end
		end
   end
   
   // Level 4
	assign index4 = path34[DEPTH-1:DEPTH-4]; // get node index to operate on
	assign del_index4 = {del4, del_path4};
	
	always @ (posedge clk or negedge rst_n) begin // Level 4
		if(!rst_n) begin : reset_L4
			integer i;
			for (i = 0; i < 16; i = i+1)	L4[i] <= 0;
		end
		else begin
			if (carry4) begin 	 
				L4[index4] <= tmp4;
			end
			else if (del4 == 1) begin
				L4[del_path4] <= tmp4;
			end
		end
   end
   
	task automatic insert_comb;

		input target_level;	// True if this is the destination level
		input [WIDTH-1:0]	node_cur; // Current data of the node
		input [WIDTH-1:0] from_top;	// Temporary buffer from level above

		output reg [WIDTH-1:0] to_bot;// Temporary buffer for level below
		output reg [WIDTH-1:0] node;	// Next data for the node
		output reg prop_next;	 	// Pass insert signal to next level

		begin
			prop_next = 0;
			node = node_cur;
			
			if(target_level) begin	// Reached target level
				node = from_top;
			end
			else begin 	// Compare and pass larger value to next level
				prop_next = 1;
				if (from_top[CMP_WID-1:0] < node[CMP_WID-1:0]) begin
					to_bot = node;
					node = from_top;
				end
				else to_bot = from_top;
			end
		end

	endtask
	
	task automatic delete_comb;
		input [DEPTH-1:0] del_index;	// Index of the node
		input [DEPTH-1:0] count;
		input [WIDTH-1:0]	child0, child1;
		input [WIDTH-1:0] from_top;	// Temporary buffer from level above

		output reg [WIDTH-1:0] to_bot;// Temporary buffer for level below
		output reg [WIDTH-1:0]	node;
		output reg del_next;	 	// Pass delete signal to next level
		output reg del_child_id; 	// Child id to be deleted

		begin
			node = from_top;
			del_next = 0;
			to_bot = 0;
			del_path2 = del_path2;
			
			if( del_index*2 + 1 <= count ) begin
				if( child0[CMP_WID-1:0] < child1[CMP_WID-1:0] ) begin
					if( child0[CMP_WID-1:0] < from_top[CMP_WID-1:0] ) begin
						node = child0;
						del_next = 1;
						to_bot = from_top;
						del_child_id = 0;
					end
				end
				else begin
					if( child1[CMP_WID-1:0] < from_top[CMP_WID-1:0] ) begin
						node = child1;
						del_next = 1;
						to_bot = from_top;
						del_child_id = 1;
					end
				end
			end
			else if( del_index*2 <= count ) begin
				if( child0[CMP_WID-1:0] < from_top[CMP_WID-1:0] ) begin
					node = child0;
					del_next = 1;
					to_bot = from_top;
					del_child_id = 0;
				end
			end
		end
   endtask
   
   function [DEPTH-1:0] find_path;
      input [DEPTH-1:0] cn;
      begin
         if (cn >= 15)
            find_path = (cn - 15)<<1;
         else if (cn >= 7)
            find_path = (cn - 7)<<2;
         else if (cn >= 3)
            find_path = (cn - 3)<<3;
         else if (cn >= 1)
            find_path = (cn - 1)<<4;
         else 
            find_path = 0;
      end
   endfunction
 
	function integer clogb2;
		input [DEPTH-1:0] value;
		integer 	i;
		begin
			clogb2 = 0;
			for(i = 0; 2**i <= value; i = i + 1)
				clogb2 = i;
		end
	endfunction
		
endmodule
