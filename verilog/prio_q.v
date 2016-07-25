`timescale 1ns / 100ps

module prio_q #(
      parameter WIDTH = 32,   // Width of data ports
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
      input                rst_n
   );

   // Heap levels
   reg  [WIDTH-1:0]        L0;
   reg  [WIDTH-1:0]        L1[1:0];
   reg  [WIDTH-1:0]        L2[3:0];
   reg  [WIDTH-1:0]        L3[7:0];
   reg  [WIDTH-1:0]        L4[15:0];

   // Data being passed down to level
   reg  [WIDTH-1:0]        tmp1;
   reg  [WIDTH-1:0]        tmp2;
   reg  [WIDTH-1:0]        tmp3;
   reg  [WIDTH-1:0]        tmp4;

   // Carry element to level
   reg                     carry1;
   reg                     carry2;
   reg                     carry3;
   reg                     carry4;

   // Path for insertion to levels
   reg  [DEPTH-1:0]        path12, path34;

   // Delete element from level
   reg                     del1;
   reg                     del2;
   reg                     del3;
   reg                     del4;

   // Node to replace/delete from level
   reg                     del_path1;
   reg  [1:0]              del_path2;
   reg  [2:0]              del_path3;
   reg  [3:0]              del_path4;

   reg  [DEPTH-1:0]        count;
   reg  [$clog2(DEPTH):0]  dest_level_prev;
   reg                     last_enq;       // If last command was an enqueue

   // Combinational elements
   // Delete operation
   reg  [WIDTH-1:0]        c_tmp1;
   reg  [WIDTH-1:0]        c_tmp2;
   reg  [WIDTH-1:0]        c_tmp3;
   reg  [WIDTH-1:0]        c_tmp4;

   reg                     c_del1;
   reg                     c_del2;
   reg                     c_del3;
   reg                     c_del4;

   reg                     c_del_id1;
   reg                     c_del_id2;
   reg                     c_del_id3;
   reg                     c_del_id4;

   reg  [WIDTH-1:0]        c_L0;
   reg  [WIDTH-1:0]        c_L1;
   reg  [WIDTH-1:0]        c_L2;
   reg  [WIDTH-1:0]        c_L3;

   // Insert operations
   reg  [WIDTH-1:0]        e_tmp1;
   reg  [WIDTH-1:0]        e_tmp2;
   reg  [WIDTH-1:0]        e_tmp3;
   reg  [WIDTH-1:0]        e_tmp4;

   reg                     e_carry1;
   reg                     e_carry2;
   reg                     e_carry3;
   reg                     e_carry4;

   reg  [WIDTH-1:0]        e_L0;
   reg  [WIDTH-1:0]        e_L1;
   reg  [WIDTH-1:0]        e_L2;
   reg  [WIDTH-1:0]        e_L3;

   // Internal wires
   // Index of nodes being operated on in each level
   wire [DEPTH-1:0]        index1;
   wire [DEPTH-1:0]        index2;
   wire [DEPTH-1:0]        index3;
   wire [DEPTH-1:0]        index4;
   wire [DEPTH-1:0]        del_index1;
   wire [DEPTH-1:0]        del_index2;
   wire [DEPTH-1:0]        del_index3;
   wire [DEPTH-1:0]        del_index4;

   wire [$clog2(DEPTH):0]  dest_level;     // level containing the first empty node

   // Output assignments
   assign out_data = L0;
   assign elem_cnt = count;
   assign full = (count == 31);
   assign empty = (count == 0);

   // Internal wires assignment
   assign dest_level = clogb2(count);

   assign index1 = path12[DEPTH-1];
   assign index2 = path12[DEPTH-1:DEPTH-2];
   assign index3 = path34[DEPTH-1:DEPTH-3];
   assign index4 = path34[DEPTH-1:DEPTH-4];

   assign del_index1 = {1'b1, del_path1};
   assign del_index2 = {1'b1, del_path2};
   assign del_index3 = {1'b1, del_path3};
   assign del_index4 = {1'b1, del_path4};

   always @ (posedge clk) begin
      if(!rst_n) begin
         count <= 0;
         path12 <= 0;
         path34 <= 0;
      end
      else begin
         // Maintain element count
         if(enq)
            count <= count + 1;
         else if(deq)
            count <= count - 1;
         else
            count <= count;

         // Find the path to the first empty node
         path12 <= find_path(count);
         path34 <= path12;

         dest_level_prev <= dest_level;
         last_enq <= (rst_n) ? enq : 0;
      end
   end

   always @* begin : comb0 // Combinational logic for root
      insert_comb(   (count == 'h0), L0, inp_data,
         e_tmp1, e_L0, e_carry1
      );

      /* The root level handles a delete operation differently than other levels.
       * So, the common delete_comb task isn't used here to find next states. */
      c_tmp1 = 0;
      c_L0 = L1[0];
      c_del1 = 0;
      c_del_id1 = 0;

      /* A delete operation takes the last occupied node to the top of the heap.
       * If the previous operation was an insertion, the last element is still
       * in the pipeline. So, tmp2 or tmp4 is taken back to the top again if carry2
       * or carry4 is true. When, the last occupied node at level 2 or 4 is being
       * replaced due to a previous delete operation, and a new delete operation
       * comes in, it reads the last node (which hasn't been replaced yet). To
       * prevent this, read tmp2 or tmp4 back to the top when element count is the
       * same as the index of the node being replaced in level 2 or 4. In all other
       * cases, take the last node to the top. The last node value will always be
       * greater than the top node. So, it is assigned to tmp1 to be passed down again.
       */
      if(carry2 || (count == del_index2 && del2))
         c_tmp1 = tmp2;
      else if(carry4 || (count == del_index4 && del4))
         c_tmp1 = tmp4;
      else if(count > 15)
         c_tmp1 = L4[count - 16];
      else if(count >7)
         c_tmp1 = L3[count - 8];
      else if(count > 3)
         c_tmp1 = L2[count - 4];
      else
         c_tmp1 = L1[1];

      /* In the case of only three elements in the heap, if the second element is
       * pushed up, the third element is assigned to tmp1, and del1 signal is sent
       * to L1 with the 2nd node as target. So, it takes the position of the 2nd
       * element. This prevents an empty Node 2 while Node 3 is occupied.
       */
      if(count > 'h2) begin
         if(L1[0][CMP_WID-1:0] >= L1[1][CMP_WID-1:0]) begin
            c_L0 = L1[1];
            c_del_id1 = 1'b1;
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
         carry1 <= enq ? e_carry1 : 0;
         del1 <= deq ? c_del1 : 0;
         if(enq) begin
            L0 <= e_L0;
            tmp1 <= e_tmp1;
         end
         else if(deq) begin
            tmp1 <= c_tmp1;
            L0 <= c_L0;
            del_path1 <= c_del_id1;
         end
      end
   end

   always @* begin : comb1 // Combinational logic for Level 1
      delete_comb(   del_index1, count,
         L2[del_path1*2], L2[del_path1*2+1],
         tmp1, c_tmp2,
         c_L1,
         c_del2, c_del_id2
      );
      insert_comb(   (dest_level == 'h1), L1[index1], tmp1,
         e_tmp2, e_L1, e_carry2
      );
   end

   always @ (negedge clk or negedge rst_n) begin // Level 1
      if(!rst_n) begin : reset_L1
         integer i;
         for (i = 0; i < 2; i = i+1)   L1[i] <= 0;
         carry2 <= 0;
         del_path2 <= 0;
      end
      else begin
         carry2 <= carry1 ? e_carry2 : 0;
         del2 <= del1 ? c_del2 : 0;
         if (carry1) begin // New data descending from upper level
            tmp2 <= e_tmp2;
            L1[index1] <= e_L1;
         end
         else if (del1 == 1) begin
            L1[del_path1] <= c_L1;
            tmp2 <= c_tmp2;
            del_path2 <= {del_path1, c_del_id2};
         end
      end
   end

   always @* begin : comb2 // Combinational logic for Level 2
      /*
       * If the dequeue operation is pending (to be executed in the following clock edge),
       * then the last element in level 3 shouldn't be considered for promotion to level 2.
       * This is done by decrementing the count by 1 with (count -deq).
       */
      delete_comb(   del_index2, (count - deq),
         L3[del_path2*2], L3[del_path2*2+1],
         tmp2, c_tmp3,
         c_L2,
         c_del3, c_del_id3
      );
      insert_comb(   (dest_level == 'h2), L2[index2], tmp2,
         e_tmp3, e_L2, e_carry3
      );
   end

   always @ (posedge clk or negedge rst_n) begin // Level 2
      if(!rst_n) begin : reset_L2
         integer i;
         for (i = 0; i < 4; i = i+1)   L2[i] <= 0;
         carry3 <= 0;
      end
      else begin
         carry3 <= (carry2 && !deq) ? e_carry3 : 0;
         del3 <= del2 ? c_del3 : 0;
         if (carry2 && !deq) begin
            /* If a dequeue is waiting to be executed in this clock edge, the descending
             * data would be taken to the top again. So, the node in Level 2 is only
             * updated if the next command isn't a dequeue.
             */
            tmp3 <= e_tmp3;
            L2[index2] <= e_L2;
         end
         else if (del2 == 1) begin
            L2[del_path2] <= c_L2;
            tmp3 <= c_tmp3;
            del_path3 <= {del_path2, c_del_id3};
         end
      end
   end

   always @* begin : comb3 // Combinational logic for Level 3
      /* If an insert was issued in last cycle, then the count has increased, but the
       * element hasn't reached level 4 yet. In this situation, a delete operation at
       * level 3 may erroneously consider the not-yet-occupied child node for promotion.
       * To prevent this, the count is decremented by 1 if last operation was an insert.
       */
      delete_comb(   del_index3, count - (last_enq ),
         L4[del_path3*2], L4[del_path3*2+1],
         tmp3, c_tmp4,
         c_L3,
         c_del4, c_del_id4
      );
      insert_comb(   (dest_level_prev == 'h3), L3[index3], tmp3,
         e_tmp4, e_L3, e_carry4
      );
   end

   always @ (negedge clk or negedge rst_n) begin // Level 3
      if(!rst_n) begin : reset_L3
         integer i;
         for (i = 0; i < 8; i = i+1)   L3[i] <= 0;
      end
      else begin
         carry4 <= carry3 ? e_carry4 : 0;
         del4 <= del3 ? c_del4 : 0;
         if (carry3) begin
            tmp4 <= e_tmp4;
            L3[index3] <= e_L3;
         end
         else if (del3 == 1) begin
            L3[del_path3] <= c_L3;
            tmp4 <= c_tmp4;
            del_path4 <= {del_path3, c_del_id4};
         end
      end
   end

   always @ (posedge clk or negedge rst_n) begin // Level 4
      if(!rst_n) begin : reset_L4
         integer i;
         for (i = 0; i < 16; i = i+1)  L4[i] <= 0;
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

      input target_level;  // True if this is the destination level
      input [WIDTH-1:0] node_cur; // Current data of the node
      input [WIDTH-1:0] from_top;   // Temporary buffer from level above

      output reg [WIDTH-1:0] to_bot;// Temporary buffer for level below
      output reg [WIDTH-1:0] node;  // Next data for the node
      output reg prop_next;      // Pass insert signal to next level

      begin
         prop_next = 0;
         node = node_cur;

         if(target_level) begin  // Reached target level
            node = from_top;
         end
         else begin  // Compare and pass larger value to next level
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
      input [DEPTH-1:0] del_index;  // Index of the node
      input [DEPTH-1:0] count;
      input [WIDTH-1:0] child0, child1;
      input [WIDTH-1:0] from_top;   // Temporary buffer from level above

      output reg [WIDTH-1:0] to_bot;// Temporary buffer for level below
      output reg [WIDTH-1:0]  node;
      output reg del_next;    // Pass delete signal to next level
      output reg del_child_id;   // Child id to be deleted

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
      integer  i;
      begin
         clogb2 = 0;
         for(i = 0; 2**i <= value; i = i + 1)
            clogb2 = i;
      end
   endfunction

endmodule
