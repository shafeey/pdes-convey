module req_buffer
   (
   clk, ireq, oreq, ack, reset 
      );
   
   input clk;
   input ireq;
   input ack;
   output oreq;
   input reset;
   
   
   localparam IDLE = 0;
   localparam REQ = 1;
   localparam DONE = 2;
   
   
   reg [1:0] r_state, c_state;
   reg c_req;
   
   always @* begin
      c_state = r_state;
      c_req = 0;
      
      case (r_state)
         IDLE: begin
            if (ireq)
               c_state = REQ;
         end
         REQ: begin
            c_req = 1;
            
            if(ack)
               c_state = DONE;
         end
         DONE: begin
            if(~ireq)
               c_state = IDLE;
         end
      endcase
   end
   
   always @(posedge clk) begin
         r_state <= reset ? IDLE : c_state;
   end
         
   assign oreq = c_req;
         
   
   
	
endmodule
