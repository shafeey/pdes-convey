module prio_q_mult #(
      parameter WIDTH = 32,   // Width of data ports
      parameter CMP_WID = 32, // Only compare CMP_WID LSBs to sort heap
      parameter DEPTH = 5     // Depth of heap, heap size = (2^DEPTH)-1 = 31
   )(
      input                clk,
      input                enq,
      input                deq,
      input  [WIDTH-1:0]   inp_data,
      output [WIDTH-1:0]   out_data,
      output [DEPTH:0]   elem_cnt,
      output               full,
      output               empty,
      input                rst_n
      );
   
   localparam NUM_HEAP=2;
   
   wire enq_int[0:NUM_HEAP-1];
   wire deq_int[0:NUM_HEAP-1];
   wire [WIDTH-1:0] out_data_int[0:NUM_HEAP-1];
   wire [DEPTH-1:0] elem_cnt_int[0:NUM_HEAP-1];
   wire full_int[0:NUM_HEAP-1];
   wire empty_int[0:NUM_HEAP-1];

   
   assign elem_cnt = elem_cnt_int[0] + elem_cnt_int[1];  
   assign full = full_int[0] & full_int[1];
   assign empty = empty_int[0] & empty_int[1];
   
   wire min_id;
   wire [CMP_WID-1:0] cmp_data[0:NUM_HEAP-1];
   assign cmp_data[0] = out_data_int[0];
   assign cmp_data[1] = out_data_int[1];
   assign min_id = ( ~empty_int[0] & ~empty_int[1] ) ? ( cmp_data[0] > cmp_data[1]) :
                        (~empty_int[1] ? 1 : 0);
   
   assign out_data = (min_id == 0) ? out_data_int[0] : out_data_int[1];
   assign deq_int[0] = min_id == 0 ? deq : 0;
   assign deq_int[1] = min_id == 1 ? deq : 0;
   
   wire ins_select;
   assign ins_select = elem_cnt_int[0] > elem_cnt_int[1];
   assign enq_int[0] = ins_select == 0 ? enq : 0;
   assign enq_int[1] = ins_select == 1 ? enq : 0;
   
   
   prio_q #(
      .WIDTH  (WIDTH  ),
      .CMP_WID(CMP_WID),
      .DEPTH  (DEPTH  )
   ) u_prio_q0 (
      .clk     (clk     ),
      .enq     (enq_int[0]     ),
      .deq     (deq_int[0]     ),
      .inp_data(inp_data),
      .out_data(out_data_int[0]),
      .elem_cnt(elem_cnt_int[0]),
      .full    (full_int[0]    ),
      .empty   (empty_int[0]   ),
      .rst_n   (rst_n   )
   );
   prio_q #(
      .WIDTH  (WIDTH  ),
      .CMP_WID(CMP_WID),
      .DEPTH  (DEPTH  )
   ) u_prio_q1 (
      .clk     (clk     ),
      .enq     (enq_int[1]     ),
      .deq     (deq_int[1]     ),
      .inp_data(inp_data),
      .out_data(out_data_int[1]),
      .elem_cnt(elem_cnt_int[1]),
      .full    (full_int[1]    ),
      .empty   (empty_int[1]   ),
      .rst_n   (rst_n   )
   );
   
endmodule
