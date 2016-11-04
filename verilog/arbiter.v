module arbiter(
   input [3:0] req,
   input stall,
   
   output [3:0] vgnt,
   output [1:0] egnt,
   output       eval,
   
   input       clk,
   input       reset
   );
	localparam NR = 4;
   localparam PIPE = 0;
   
   reg [1:0] last_gnt;
   reg       last_vld;
   
   wire [3:0] arb_vgnt;
   wire [1:0] arb_egnt;
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


   
