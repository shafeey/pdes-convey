/*
	LFSR module uses a 16 bit Linear Feedback Shift Register with 
	a Fibonacci scheme. It computes NBITS bits at once instead of
	one bit at a time.
	It generates the next random value only when the 'next' control
	is asserted.
*/

module LFSR
	#(parameter NBITS = 8) //Number of bits in each generation
	(
    input clk,
    input rst_n,
	input next,
	input [15:0] seed,
    output [NBITS-1:0] rnd
	);

	
reg [15:0] data, data_next;

always @* begin
	data_next = data;
	repeat(NBITS) begin : taps
		data_next = {data_next[14:0],
						(data_next[15] ^ data_next[14] ^ data_next[12] ^ data_next[3])
					};
	end
end

always @(posedge clk or negedge rst_n) begin
	data <= (!rst_n) ? seed :	// Initialize with a random seed provided by the parent module
				next ? data_next : data;
end

assign rnd = data[NBITS-1:0];

endmodule