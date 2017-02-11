module hist_table#(
   parameter WIDTH = 32,
   parameter DEPTH = 256,
   parameter ADDR_WID = 8
) (
  clka,
  wea,
  addra,
  dina,
  douta
);

input clka;
input [0 : 0] wea;
input [ADDR_WID-1 : 0] addra;
input [WIDTH-1: 0] dina;
output [WIDTH-1: 0] douta;


reg [WIDTH-1:0] ram [0:DEPTH-1];

always @(posedge clka) begin
   if(wea) begin
      ram[addra] <= dina;
   end
   
end

assign douta = ram[addra];

endmodule
