module dummy_mc #(
      parameter MC_RTNCTL_WIDTH = 32,
      parameter RAM_DEPTH = 64
   )(
      input                            clk,
      input                            mc_rq_vld,
      input      [2:0]                 mc_rq_cmd,
      input      [3:0]                 mc_rq_scmd,
      input      [47:0]                mc_rq_vadr,
      input      [1:0]                 mc_rq_size,
      input      [MC_RTNCTL_WIDTH-1:0] mc_rq_rtnctl,
      input      [63:0]                mc_rq_data,
      input                            mc_rq_flush,
      output reg                       mc_rq_stall,
      output reg                       mc_rs_vld,
      output reg [2:0]                 mc_rs_cmd,
      output reg [3:0]                 mc_rs_scmd,
      output reg [MC_RTNCTL_WIDTH-1:0] mc_rs_rtnctl,
      output reg [63:0]                mc_rs_data,
      input                            mc_rs_stall,
      input                            reset
   );
   `include "aemc_messages.vh"

   localparam                         BUF_SIZE               = 4;

   reg        [63:0]                  mem [0:RAM_DEPTH/8-1];
   reg        [MC_RTNCTL_WIDTH +57:0] req_buf [0:BUF_SIZE-1];
   reg        [63:0]                  data_buf[0:BUF_SIZE-1];

   wire                               rq_vld;
   wire       [2:0]                   rq_cmd;
   wire       [3:0]                   rq_scmd;
   wire       [47:0]                  rq_vadr;
   wire       [1:0]                   rq_size;
   wire       [MC_RTNCTL_WIDTH-1:0]   rq_rtnctl;
   wire       [63:0]                  rq_data;

   assign rq_vld = req_buf[0][0];
   assign rq_cmd = req_buf[0][1 +: 3];
   assign rq_scmd = req_buf[0][4 +: 4];
   assign rq_vadr = req_buf[0][8 +: 48];
   assign rq_size = req_buf[0][56 +: 2];
   assign rq_rtnctl = req_buf[0][58 +: MC_RTNCTL_WIDTH];
   assign rq_data = data_buf[0];

   always @(posedge clk) begin : buffer  // Introduce 4 cycle delay in response
      integer i;
      for(i = 0; i < BUF_SIZE-1; i = i + 1) begin
         req_buf[i] <= reset ? 0 : req_buf[i+1];
         data_buf[i] <= reset ? 0 : data_buf[i+1];
      end
      req_buf[BUF_SIZE-1] <= reset ? 0 :
                              (mc_rq_vld ?
                                 {mc_rq_rtnctl, mc_rq_size, mc_rq_vadr, mc_rq_scmd, mc_rq_cmd, mc_rq_vld} :
                                 0);
      data_buf[BUF_SIZE-1] <= reset ? 0 : mc_rq_data;

   end

   always @(posedge clk) begin
      if(rq_vld) begin // Has a valid request
         if(rq_cmd == AEMC_CMD_WR8) begin
            $display("MEMORY: Write request at %d, Data: %h", rq_vadr, rq_data);
            mem[rq_vadr>>3] = rq_data;
            mc_rs_cmd = MCAE_CMD_WR_CMP;
         end
         else if(rq_cmd == AEMC_CMD_RD8) begin
            $display("MEMORY: Read request at %d, Data: %h", rq_vadr, mem[rq_vadr>>3]);
            mc_rs_cmd = MCAE_CMD_RD8_DATA;
         end
      end
      else mc_rs_cmd = 0;

      mc_rs_scmd = (rq_vld) ? rq_scmd : 0;
      mc_rs_rtnctl = (rq_vld) ? rq_rtnctl : 0;
      mc_rs_data = (rq_vld) ? mem[rq_vadr>>3] : 0;
      mc_rs_vld = rq_vld;

      mc_rq_stall = 0;
   end
   
   always @(posedge clk) begin
      if(mc_rq_vld && (mc_rq_vadr >= RAM_DEPTH)) // Trying to access memory outside allocation
         $display("ERROR: Memory access at invalid address: Addr %d, %2d", mc_rq_vadr, mc_rq_rtnctl);
   end

endmodule
