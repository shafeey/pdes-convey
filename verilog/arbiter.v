module arbiter#(
   parameter NR = 4 // Number of requesters
   )
   (
   input [NR-1:0] req,
   input stall,
   
   output [NR-1:0] vgnt,
   output [$clog2(NR)-1:0] egnt,
   output       eval,
   
   input       clk,
   input       reset
   );
   localparam PIPE = 1; // Pipeline stages: 0~2
   
   reg [$clog2(NR)-1:0] last_gnt;
   reg       last_vld;
   
   wire [NR-1:0] arb_vgnt;
   wire [$clog2(NR)-1:0] arb_egnt;
   wire arb_eval;
   
   /* Keep track of the last granted line */
   always @(posedge clk) begin
      last_gnt <= (reset) ? 0 : egnt;
      last_vld <= (reset) ? 0 : eval;
   end

   /* If the last granted line still has requests, override the grant */
   assign egnt = (last_vld && req[last_gnt]) ? last_gnt : arb_egnt;
   assign vgnt = eval << egnt;
   assign eval = arb_eval;
   
   rrarb #(
      .NR  (NR  ),
      .PIPE(PIPE)
   ) dut (
      .clk  (clk  ),
      .reset(reset),
      .req  (req  ),
      .stall(1'b0),
      .vgnt (arb_vgnt ),
      .eval (arb_eval ),
      .egnt (arb_egnt )
   );
   
endmodule


   
