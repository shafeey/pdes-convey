`timescale 1ns / 1ps

`define DWIDTH 16 // Width of DATA BUS
`define HDEPTH 5  // Depth of heap

module prio_q_tb( );

   reg                   clk;
   reg                   rst_n;
   reg                   enq;
   reg                   deq;
   reg                   done;

   reg     [`DWIDTH-1:0] inp_data;
   wire    [`DWIDTH-1:0] out_data;
   wire    [`HDEPTH-1:0] count;

   integer               data_file; // file handler
   integer               scan_file; // file handler
   integer               cycle_num; // Current clock cycle count;

   initial begin
      clk       = 1'b0;
      rst_n     = 1'b0;
      done      = 1'b0;
      cycle_num = 0;

      #20
      rst_n     = 1'b1;

      @(posedge done); // After all data has been read
      rst_n     = 1'b0;

      #10 $finish;
   end

   always
      #5 clk = !clk;

   always @(posedge clk) begin
      cycle_num = cycle_num + 1;
   end

   initial begin // Read stimuli from data file
      @(posedge rst_n);
      data_file = $fopen("testbenches/prio_q_test_data.dat", "r");
      if (data_file == 0) begin
         $display("Error opening data file");
         $finish;
      end

      // Read from file and drive test stimuli
      @(posedge clk);
      while (!$feof(data_file)) begin
         // Input data patter : <enq>, <deq>, <data>
         scan_file = $fscanf(data_file, "%b, %b, %d\n",
            enq, deq, inp_data);
         if(!scan_file) $display("Error reading data file");
         @(posedge clk);
      end

      done      = 1'b1; // Finished reading all data
      $fclose(data_file);
   end

   always @(posedge clk) begin
      if(count == 16)
         $display("Error: Invalid number of elements in the queue");
      if(deq && inp_data != out_data)
         $display("Dequeue mismatch: Cycle %d, Count %d, Expected %d, Actual %d",
            cycle_num, count, inp_data, out_data);
   end

// Instantiate module under test
   prio_q DUT (
      .CLK(clk),
      .rst_n(rst_n),
      .enq (enq),
      .deq (deq),
      .inp_data({16'b0, inp_data}),
      .out_data(out_data),
      .count(count)
   );

endmodule
