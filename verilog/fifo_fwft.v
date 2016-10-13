module fwft_fifo( rst, clk,
                  rd_en, dout, empty, full, data_count,                
                  wr_en, din);

   parameter width = 32;
   parameter DEPTH = 16;
   
   input                 rst;
   input                 clk;
   input                 rd_en;
   input                 wr_en;
   input [(width-1):0]   din;
   output                empty;
   output                full;
   output [(width-1):0]  dout;
   output reg [3:0]      data_count;

   wire we;

   reg [3:0] head, tail;
   reg looped;
   
   // Memory pointer management
   always @(posedge clk) begin 
      if(rst) begin
         head <= 0;
         tail <= 0;
         looped <= 0;
         data_count <= 0;
      end
      else begin
         if(rd_en == 1'b1) begin
            if(looped || head != tail) begin
               // Update tail pointer
               if(tail == DEPTH -1 ) begin
                  tail <= 0;
                  looped <= 0;
               end else
                  tail <= tail + 1;
            end
         end

         if(wr_en == 1) begin
            if(looped == 0 || head != tail) begin
               // Update head pointer
               if(head == DEPTH -1) begin
                  head <= 0;
                  looped <= 1;
               end
               else
                  head <= head + 1;
            end
         end
         
         if(rd_en && ~empty)
            data_count <= data_count -1;
         else if(wr_en && ~full)
            data_count <= data_count + 1;
         else 
            data_count <= data_count;
      end
   end
   
   assign full = (head == tail && looped) ? 1 : 0;
   assign empty = (head == tail && ~looped) ? 1: 0;

   assign we = wr_en && (looped == 0 || head != tail);



   memory fifo_mem(
     .a(head), // input [3 : 0] a
     .d(din), // input [31 : 0] d
     .dpra(tail), // input [3 : 0] dpra
     .clk(clk), // input clk
     .we(we), // input we
     .dpo(dout) // output [31 : 0] dpo
   );
   
endmodule

module memory(
  a,
  d,
  dpra,
  clk,
  we,
  dpo
);

input [3 : 0] a;
input [31 : 0] d;
input [3 : 0] dpra;
input clk;
input we;
output [31 : 0] dpo;

// synthesis translate_off

  DIST_MEM_GEN_V7_2 #(
    .C_ADDR_WIDTH(4),
    .C_DEFAULT_DATA("0"),
    .C_DEPTH(16),
    .C_FAMILY("artix7"),
    .C_HAS_CLK(1),
    .C_HAS_D(1),
    .C_HAS_DPO(1),
    .C_HAS_DPRA(1),
    .C_HAS_I_CE(0),
    .C_HAS_QDPO(0),
    .C_HAS_QDPO_CE(0),
    .C_HAS_QDPO_CLK(0),
    .C_HAS_QDPO_RST(0),
    .C_HAS_QDPO_SRST(0),
    .C_HAS_QSPO(0),
    .C_HAS_QSPO_CE(0),
    .C_HAS_QSPO_RST(0),
    .C_HAS_QSPO_SRST(0),
    .C_HAS_SPO(0),
    .C_HAS_SPRA(0),
    .C_HAS_WE(1),
    .C_MEM_INIT_FILE("no_coe_file_loaded"),
    .C_MEM_TYPE(4),
    .C_PARSER_TYPE(1),
    .C_PIPELINE_STAGES(0),
    .C_QCE_JOINED(0),
    .C_QUALIFY_WE(0),
    .C_READ_MIF(0),
    .C_REG_A_D_INPUTS(0),
    .C_REG_DPRA_INPUT(0),
    .C_SYNC_ENABLE(1),
    .C_WIDTH(32)
  )
  inst (
    .A(a),
    .D(d),
    .DPRA(dpra),
    .CLK(clk),
    .WE(we),
    .DPO(dpo),
    .SPRA(),
    .I_CE(),
    .QSPO_CE(),
    .QDPO_CE(),
    .QDPO_CLK(),
    .QSPO_RST(),
    .QDPO_RST(),
    .QSPO_SRST(),
    .QDPO_SRST(),
    .SPO(),
    .QSPO(),
    .QDPO()
  );

// synthesis translate_on

endmodule
