module pheap #(
      parameter WIDTH = 32,   // Width of data ports
      parameter CMP_WID = 32, // Only compare CMP_WID LSBs to sort heap
      parameter DEPTH = 6     // Depth of heap, heap size = (2^DEPTH)-1 = 31
   )(
      input                clk,
      input                enq,
      input                deq,
      input  [WIDTH-1:0]   inp_data,
      output [WIDTH-1:0]   out_data,
      output [DEPTH-1:0]   elem_cnt,
      output               full,
      output               empty,
      output               ready,
      input                rst_n
      );
   
   wire [DEPTH-1:0] index0;
   wire [DEPTH-1:0] index1;
   wire [DEPTH-1:0] index2;
   wire [DEPTH-1:0] index3;
   wire [DEPTH-1:0] index4;
   wire [DEPTH-1:0] index5;
   
   reg [DEPTH-1:0] trans_idx[0:DEPTH-1];
   reg [WIDTH-1:0] trans_val[0:DEPTH-1];
   
   localparam NOP = 0;
   localparam ENQ = 1;
   localparam DEQ = 2;
   localparam ENQ_DEQ = 3;
   
   reg [1:0] operation[0:DEPTH-1];
   
   reg [DEPTH-1:0] L0_cap, L1_cap[0:1], L2_cap[0:3], L3_cap[0:7], L4_cap[0:15], L5_cap[0:31];
   reg L0_occupied;
   reg [0:0] L1_left_occupied, L1_right_occupied;
   reg [1:0] L2_left_occupied, L2_right_occupied;
   reg [3:0] L3_left_occupied, L3_right_occupied;
   reg [7:0] L4_left_occupied, L4_right_occupied;
   reg [15:0] L5_left_occupied, L5_right_occupied;
   
   reg [WIDTH-1:0] L0;
   reg [WIDTH-1:0] L1_left[0:0], L1_right[0:0];
   reg [WIDTH-1:0] L2_left[0:1], L2_right[0:1];
   reg [WIDTH-1:0] L3_left[0:3], L3_right[0:3];
   reg [WIDTH-1:0] L4_left[0:7], L4_right[0:7];
   reg [WIDTH-1:0] L5_left[0:15], L5_right[0:15];
   
   reg [WIDTH-1:0] next_val0, next_val1, next_val2, next_val3, next_val4, next_val5;
   reg c_occupied0, c_occupied1, c_occupied2, c_occupied3, c_occupied4, c_occupied5;
   reg [DEPTH-1:0] next_cap0, next_cap1, next_cap2, next_cap3, next_cap4, next_cap5;     
   reg next_side1, next_side2, next_side3, next_side4, next_side5, next_side6;
   reg [1:0] next_op1, next_op2, next_op3, next_op4, next_op5, next_op6;
   
   localparam LEFT = 0;
   localparam RIGHT = 1;
   
   reg [WIDTH-1:0] next_trans_val1, next_trans_val2, next_trans_val3, next_trans_val4, next_trans_val5, next_trans_val6;
   
   assign index0 = 0;
   assign index1 = trans_idx[1];
   assign index2 = trans_idx[2];
   assign index3 = trans_idx[3];
   assign index4 = trans_idx[4];
   assign index5 = trans_idx[5];
   
   assign out_data = L0;
   
   wire [1:0] inp_op;
   assign inp_op = {deq, enq};
   
   reg [DEPTH-1:0] count;
   always @(posedge clk) begin // element count
      if(~rst_n) begin
         count <= 0;
      end
      else begin
         case (inp_op)
            ENQ: count <= count + 1;
            DEQ: count <= count - 1;
            default: count <= count;
         endcase
      end
   end
   
   localparam MAX_SIZE = (2**DEPTH) - 1;
   assign full = count == MAX_SIZE;
   assign empty = count == 0;
   assign elem_cnt = count;
         
   always @* begin : L0_control // control signal generation 1
      enque(inp_data, L0, L0_occupied, inp_op, L0_cap, L1_cap[{index0,1'b0}],
            L1_left[index0], L1_left_occupied[index0], L1_right[index0], L1_right_occupied[index0],
            next_val0, c_occupied0, next_cap0, next_trans_val1, next_op1, next_side1);
   end
   
   wire [WIDTH-1:0] cur_val1;
   assign cur_val1 = (index1[0] == LEFT) ? L1_left[index1[DEPTH-1:1]] : L1_right[index1[DEPTH-1:1]];
   wire cur_occupied1;
   assign cur_occupied1 = (index1[0] == LEFT) ? L1_left_occupied[index1[DEPTH-1:1]] : L1_right_occupied[index1[DEPTH-1:1]];
   always @* begin : L1_control
      enque(trans_val[1], cur_val1, cur_occupied1, operation[1], L1_cap[index1], L2_cap[{index1, 1'b0}],
            L2_left[index1], L2_left_occupied[index1], L2_right[index1], L2_right_occupied[index1],
            next_val1, c_occupied1, next_cap1, next_trans_val2, next_op2, next_side2);
   end
   
   wire [WIDTH-1:0] cur_val2;
   assign cur_val2 = (index2[0] == LEFT) ? L2_left[index2[DEPTH-1:1]] : L2_right[index2[DEPTH-1:1]];
   wire cur_occupied2;
   assign cur_occupied2 = (index2[0] == LEFT) ? L2_left_occupied[index2[DEPTH-1:1]] : L2_right_occupied[index2[DEPTH-1:1]];
   always @* begin : L2_control
      enque(trans_val[2], cur_val2, cur_occupied2, operation[2], L2_cap[index2], L3_cap[{index2, 1'b0}],
            L3_left[index2], L3_left_occupied[index2], L3_right[index2], L3_right_occupied[index2],
            next_val2, c_occupied2, next_cap2, next_trans_val3, next_op3, next_side3);
   end
      
   wire [WIDTH-1:0] cur_val3;
   assign cur_val3 = (index3[0] == LEFT) ? L3_left[index3[DEPTH-1:1]] : L3_right[index3[DEPTH-1:1]];
   wire cur_occupied3;
   assign cur_occupied3 = (index3[0] == LEFT) ? L3_left_occupied[index3[DEPTH-1:1]] : L3_right_occupied[index3[DEPTH-1:1]];
   always @* begin : L3_control
      enque(trans_val[3], cur_val3, cur_occupied3, operation[3], L3_cap[index3], L4_cap[{index3, 1'b0}],
            L4_left[index3], L4_left_occupied[index3], L4_right[index3], L4_right_occupied[index3],
            next_val3, c_occupied3, next_cap3, next_trans_val4, next_op4, next_side4);
   end
         
   wire [WIDTH-1:0] cur_val4;
   assign cur_val4 = (index4[0] == LEFT) ? L4_left[index4[DEPTH-1:1]] : L4_right[index4[DEPTH-1:1]];
   wire cur_occupied4;
   assign cur_occupied4 = (index4[0] == LEFT) ? L4_left_occupied[index4[DEPTH-1:1]] : L4_right_occupied[index4[DEPTH-1:1]];
   always @* begin : L4_control
      enque(trans_val[4], cur_val4, cur_occupied4, operation[4], L4_cap[index4], L5_cap[{index4, 1'b0}],
            L5_left[index4], L5_left_occupied[index4], L5_right[index4], L5_right_occupied[index4],
            next_val4, c_occupied4, next_cap4, next_trans_val5, next_op5, next_side5);
   end
         
   wire [WIDTH-1:0] cur_val5;
   assign cur_val5 = (index5[0] == LEFT) ? L5_left[index5[DEPTH-1:1]] : L5_right[index5[DEPTH-1:1]];
   wire cur_occupied5;
   assign cur_occupied5 = (index5[0] == LEFT) ? L5_left_occupied[index5[DEPTH-1:1]] : L5_right_occupied[index5[DEPTH-1:1]];
   always @* begin : L5_control
      enque(trans_val[5], cur_val5, cur_occupied5, operation[5], L5_cap[index5], 0,
            0, 0, 0, 0,
            next_val5, c_occupied5, next_cap5, next_trans_val6, next_op6, next_side6);
   end

   always@(posedge clk) begin
      if(~rst_n) begin : reset0
         L0_occupied <= 0;
      end
      else begin      
         L0 <= next_val0;
         L0_occupied <= c_occupied0;
         trans_val[1] <= next_trans_val1;
         trans_idx[1] <= {index0[DEPTH-2:0], next_side1};
         operation[1] <= next_op1;
      end
   end
   
   
   always@(posedge clk) begin
      if(~rst_n) begin : reset1
         integer i;
         for(i=0; i<2; i=i+1) begin
            L1_cap[i] <= 31;
            L1_left_occupied[i] <= 0;
            L1_right_occupied[i] <= 0;
         end
      end
      else begin
         if(operation[1] != NOP) begin
            L1_cap[index1] <= next_cap1;
            if(index1[0] == LEFT) begin
               L1_left[index1[DEPTH-1:1]] <= next_val1;
               L1_left_occupied[index1[DEPTH-1:1]] <= c_occupied1;
            end 
            else begin
               L1_right[index1[DEPTH-1:1]] <= next_val1;
               L1_right_occupied[index1[DEPTH-1:1]] <= c_occupied1;
            end 
         end
         
         trans_val[2] <= next_trans_val2;
         trans_idx[2] <= {index1[DEPTH-2:0], next_side2};
         operation[2] <= next_op2;
      end
   end
      
   always@(posedge clk) begin
      if(~rst_n) begin : reset2
         integer i;
         for(i=0; i<4; i=i+1) begin
            L2_cap[i] <= 15;
            L2_left_occupied[i] <= 0;
            L2_right_occupied[i] <= 0;
         end
      end
      else begin
         if(operation[2] != NOP) begin
            L2_cap[index2] <= next_cap2;
            if(index2[0] == LEFT) begin
               L2_left[index2[DEPTH-1:1]] <= next_val2;
               L2_left_occupied[index2[DEPTH-1:1]] <= c_occupied2;
            end 
            else begin
               L2_right[index2[DEPTH-1:1]] <= next_val2;
               L2_right_occupied[index2[DEPTH-1:1]] <= c_occupied2;
            end 
         end
         
         trans_val[3] <= next_trans_val3;
         trans_idx[3] <= {index2[DEPTH-2:0], next_side3};
         operation[3] <= next_op3;
      end
   end
         
   always@(posedge clk) begin
      if(~rst_n) begin : reset3
         integer i;
         for(i=0; i<8; i=i+1) begin
            L3_cap[i] <= 7;
            L3_left_occupied[i] <= 0;
            L3_right_occupied[i] <= 0;
         end
      end
      else begin
         if(operation[3] != NOP) begin
            L3_cap[index3] <= next_cap3;
            if(index3[0] == LEFT) begin
               L3_left[index3[DEPTH-1:1]] <= next_val3;
               L3_left_occupied[index3[DEPTH-1:1]] <= c_occupied3;
            end 
            else begin
               L3_right[index3[DEPTH-1:1]] <= next_val3;
               L3_right_occupied[index3[DEPTH-1:1]] <= c_occupied3;
            end 
         end
         
         trans_val[4] <= next_trans_val4;
         trans_idx[4] <= {index3[DEPTH-2:0], next_side4};
         operation[4] <= next_op4;
      end 
   end
            
   always@(posedge clk) begin
      if(~rst_n) begin : reset4
         integer i;
         for(i=0; i<16; i=i+1) begin
            L4_cap[i] <= 3;
            L4_left_occupied[i] <= 0;
            L4_right_occupied[i] <= 0;
         end
      end
      else begin
         if(operation[4] != NOP) begin
            L4_cap[index4] <= next_cap4;
            if(index4[0] == LEFT) begin
               L4_left[index4[DEPTH-1:1]] <= next_val4;
               L4_left_occupied[index4[DEPTH-1:1]] <= c_occupied4;
            end 
            else begin
               L4_right[index4[DEPTH-1:1]] <= next_val4;
               L4_right_occupied[index4[DEPTH-1:1]] <= c_occupied4;
            end 
         end
         trans_val[5] <= next_trans_val5;
         trans_idx[5] <= {index4[DEPTH-2:0], next_side5};
         operation[5] <= next_op5;
      end
   end
            
   always@(posedge clk) begin
      if(~rst_n) begin : reset5
         integer i;
         for(i=0; i<32; i=i+1) begin
            L5_cap[i] <= 1;
            L5_left_occupied[i] <= 0;
            L5_right_occupied[i] <= 0;
         end
      end
      else begin
         if(operation[5] != NOP) begin
            L5_cap[index5] <= next_cap5;
            if(index5[0] == LEFT) begin
               L5_left[index5[DEPTH-1:1]] <= next_val5;
               L5_left_occupied[index5[DEPTH-1:1]] <= c_occupied5;
            end 
            else begin
               L5_right[index5[DEPTH-1:1]] <= next_val5;
               L5_right_occupied[index5[DEPTH-1:1]] <= c_occupied5;
            end 
         end
      end
   end

   reg state;
   always @(posedge clk) begin
      state <= rst_n ? enq : 0;
   end
   assign ready = ~(state | enq);
   
   task automatic enque;
      input [WIDTH-1:0] val;
      input [WIDTH-1:0] cur_val;
      input occupied;
      input [1:0] cur_op;
      input [DEPTH-1:0] cur_capacity;
      input [DEPTH-1:0] child_capacity;
      input [WIDTH-1:0] child_left;
      input child_left_vld;
      input [WIDTH-1:0] child_right;
      input child_right_vld;
      
      output reg [WIDTH-1:0] next_val;
      output reg c_occupied;
      output reg [DEPTH-1:0] next_capacity;
      output reg [WIDTH-1:0] next_trans_val;
      output reg [1:0] next_op;
      output reg side;
      
      begin : task_group
         c_occupied = occupied;
         next_trans_val = val;
         next_val = cur_val;
         next_capacity = cur_capacity;
         side = 0;
         next_op = NOP;
         
         if(cur_op == ENQ) begin
            c_occupied = 1;
            next_capacity = cur_capacity -1;
            side =  child_capacity > 0 ? LEFT : RIGHT; 
            
            if(occupied) begin
               next_op = ENQ;
               if(val[0 +: CMP_WID] < cur_val[0 +: CMP_WID]) begin
                  next_val = val;
                  next_trans_val = cur_val;
               end
            end
            else begin
               next_val = val;
            end
         end
         else if(cur_op == DEQ) begin
            next_capacity = cur_capacity + 1;
            next_op = DEQ;
            if(child_left_vld && child_right_vld) begin
               if(child_left[0 +: CMP_WID] < child_right[0 +: CMP_WID]) begin
                  next_val = child_left;
                  side = LEFT;
               end
               else begin
                  next_val = child_right;
                  side = RIGHT;
               end
            end
            else if(child_left_vld) begin
               next_val = child_left;
               side = LEFT;
            end 
            else if(child_right_vld) begin
               next_val = child_right;
               side = RIGHT;
            end
            else begin
               next_op = NOP;
               next_val = 0;
               c_occupied = 0;
            end
         end
         
      end
   endtask
   
endmodule
