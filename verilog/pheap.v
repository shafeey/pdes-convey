module pheap #(
      parameter WIDTH = 16,   // Width of data ports
      parameter CMP_WID = 32, // Only compare CMP_WID LSBs to sort heap
      parameter DEPTH = 5     // Depth of heap, heap size = (2^DEPTH)-1 = 31
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
   
   wire [4:0] index0;
   wire [4:0] index1;
   wire [4:0] index2;
   wire [4:0] index3;
   wire [4:0] index4;
   
   reg [4:0] trans_idx[0:4];
   reg [WIDTH-1:0] trans_val[0:4];
   
   localparam NOP = 0;
   localparam ENQ = 1;
   localparam DEQ = 2;
   localparam ENQ_DEQ = 3;
   
   reg [1:0] operation[0:4];
   
   reg [3:0] L0_cap, L1_cap[0:1], L2_cap[0:3], L3_cap[0:7], L4_cap[0:15];
   reg L0_occupied;
   reg [1:0] L1_occupied;
   reg [3:0] L2_occupied;
   reg [7:0] L3_occupied;
   reg [15:0] L4_occupied;
   
   reg [WIDTH-1:0] L0;
   reg [WIDTH-1:0] L1_left[0:0], L1_right[0:0];
   reg [WIDTH-1:0] L2_left[0:1], L2_right[0:1];
   reg [WIDTH-1:0] L3_left[0:3], L3_right[0:3];
   reg [WIDTH-1:0] L4_left[0:7], L4_right[0:7];
   
   reg [WIDTH-1:0] next_val1, next_val2, next_val3, next_val4, next_val5;
   reg c_occupied1, c_occupied2, c_occupied3, c_occupied4, c_occupied5;
   reg c_active2;
   reg [3:0] next_capacity1, next_capacity2, next_capacity3, next_capacity4, next_capacity5;     
   reg next_side1, next_side2, next_side3, next_side4, next_side5;
   reg [1:0] next_op1, next_op2, next_op3, next_op4, next_op5;
   
   localparam LEFT = 0;
   localparam RIGHT = 1;
   
   reg [WIDTH-1:0] next_trans_val1, next_trans_val2, next_trans_val3, next_trans_val4, next_trans_val5;
   
   assign index0 = 0;
   assign index1 = trans_idx[1];
   assign index2 = trans_idx[2];
   assign index3 = trans_idx[3];
   assign index4 = trans_idx[4];
   
   assign out_data = L0;
   
   wire [1:0] inp_op;
   assign inp_op = {deq, enq};
   
   reg [4:0] count;
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
   assign full = count == 31;
   assign empty = count == 0;
   assign elem_cnt = count;
         
   always @* begin : L0_control // control signal generation 1
      enque(inp_data, L0, L0_occupied, inp_op, L0_cap, L1_cap[{index0,1'b0}],
            L1_left[index0], L1_occupied[{index0, 1'b0}], L1_right[index0], L1_occupied[{index0, 1'b1}],
            next_val1, next_trans_val1, c_occupied1, next_capacity1, next_side1, next_op1);
   end
   
   wire [WIDTH-1:0] cur_val1;
   assign cur_val1 = (index1[0] == LEFT) ? L1_left[index1[4:1]] : L1_right[index1[4:1]];
   always @* begin : L1_control
      enque(trans_val[1], cur_val1, L1_occupied[index1], operation[1], L1_cap[index1], L2_cap[{index1, 1'b0}],
            L2_left[index1], L2_occupied[{index1, 1'b0}], L2_right[index1], L2_occupied[{index1, 1'b1}],
            next_val2, next_trans_val2, c_occupied2, next_capacity2, next_side2, next_op2);
   end
   
   wire [WIDTH-1:0] cur_val2;
   assign cur_val2 = (index2[0] == LEFT) ? L2_left[index2[4:1]] : L2_right[index2[4:1]];
   always @* begin : L2_control
      enque(trans_val[2], cur_val2, L2_occupied[index2], operation[2], L2_cap[index2], L3_cap[{index2, 1'b0}],
            L3_left[index2], L3_occupied[{index2, 1'b0}], L3_right[index2], L3_occupied[{index2, 1'b1}],
            next_val3, next_trans_val3, c_occupied3, next_capacity3, next_side3, next_op3);
   end
      
   wire [WIDTH-1:0] cur_val3;
   assign cur_val3 = (index3[0] == LEFT) ? L3_left[index3[4:1]] : L3_right[index3[4:1]];
   always @* begin : L3_control
      enque(trans_val[3], cur_val3, L3_occupied[index3], operation[3], L3_cap[index3], L4_cap[{index3, 1'b0}],
            L4_left[index3], L4_occupied[{index3, 1'b0}], L4_right[index3], L4_occupied[{index3, 1'b1}],
            next_val4, next_trans_val4, c_occupied4, next_capacity4, next_side4, next_op4);
   end
         
   wire [WIDTH-1:0] cur_val4;
   assign cur_val4 = (index4[0] == LEFT) ? L4_left[index4[4:1]] : L4_right[index4[4:1]];
   always @* begin : L4_control
      enque(trans_val[4], cur_val4, L4_occupied[index4], operation[4], L4_cap[index4], 0,
            0, 0, 0, 0,
            next_val5, next_trans_val5, c_occupied5, next_capacity5, next_side5, next_op5);
   end
   
   always @(posedge clk) begin
      if(~rst_n) begin : reset_cap1
         integer i;
         L0_occupied <= 0;
         for(i=0; i<2; i=i+1) begin
            L1_cap[i] <= 15;
            L1_occupied[i] <= 0;
         end
         for(i=0; i<4; i=i+1) begin
            L2_cap[i] <= 7;
            L2_occupied[i] <= 0;
         end
         for(i=0; i<8; i=i+1) begin
            L3_cap[i] <= 3;
            L3_occupied[i] <= 0;
         end
         for(i=0; i<16; i=i+1) begin
            L4_cap[i] <= 1;
            L4_occupied[i] <= 0;
         end
      end
      else begin
         if(operation[1] != NOP) begin
            L1_cap[index1] <= next_capacity2;
            L1_occupied[index1] <= c_occupied2;
         end
         
         if(operation[2] != NOP) begin
            L2_cap[index2] <= next_capacity3;
            L2_occupied[index2] <= c_occupied3;
         end
         
         if(operation[3] != NOP) begin
            L3_cap[index3] <= next_capacity4;
            L3_occupied[index3] <= c_occupied4;
         end
                  
         if(operation[4] != NOP) begin
            L4_cap[index4] <= next_capacity5;
            L4_occupied[index4] <= c_occupied5;
         end
         
         L0_occupied <= c_occupied1;
      end
   end
   
   
   always@(posedge clk) begin
         L0 <= next_val1;
      trans_val[1] <= next_trans_val1;
      trans_idx[1] <= {index0[2:0], next_side1};
      operation[1] <= next_op1;
   end
   
   
   always@(posedge clk) begin
      if(operation[1] != NOP) begin
         if(index1[0] == LEFT)
            L1_left[index1[4:1]] <= next_val2;
         else
            L1_right[index1[4:1]] <= next_val2;
      end
      
      trans_val[2] <= next_trans_val2;
      trans_idx[2] <= {index1[3:0], next_side2};
      operation[2] <= next_op2;
   end
      
   always@(posedge clk) begin
      if(operation[2] != NOP) begin
         if(index2[0] == LEFT)
            L2_left[index2[4:1]] <= next_val3;
         else
            L2_right[index2[4:1]] <= next_val3;
      end
      
      trans_val[3] <= next_trans_val3;
      trans_idx[3] <= {index2[3:0], next_side3};
      operation[3] <= next_op3;
   end
         
   always@(posedge clk) begin
      if(operation[3] != NOP) begin
         if(index3[0] == LEFT)
            L3_left[index3[4:1]] <= next_val4;
         else
            L3_right[index3[4:1]] <= next_val4;
      end
      
      trans_val[4] <= next_trans_val4;
      trans_idx[4] <= {index3[3:0], next_side4};
      operation[4] <= next_op4;
   end
            
   always@(posedge clk) begin
      if(operation[4] != NOP) begin
         if(index4[0] == LEFT)
            L4_left[index4[4:1]] <= next_val5;
         else
            L4_right[index4[4:1]] <= next_val5;
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
      input [3:0] cur_capacity;
      input [3:0] child_capacity;
      input [WIDTH-1:0] child_left;
      input child_left_vld;
      input [WIDTH-1:0] child_right;
      input child_right_vld;
      
      output reg [WIDTH-1:0] next_val;
      output reg [WIDTH-1:0] next_trans_val;
      output reg c_occupied;
      output reg [3:0] next_capacity;
      output reg side;
      output reg [1:0] next_op;
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
               if(val < cur_val) begin
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
               if(child_left < child_right) begin
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
