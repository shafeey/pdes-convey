`timescale 1ns / 1ps

//`define PRIO_Q_DUMP_HEAP_CONTENTS // Writes heap values to file for debug
`define DWIDTH 16 // Width of DATA BUS
`define HDEPTH 6  // Depth of heap

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
      cycle_num = (rst_n && !done) ? cycle_num + 1 : 0;
   end

   initial begin // Read stimuli from data file
      enq = 0;
      deq = 0;
      inp_data = 0;
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
            enq = 0; deq = 0; inp_data = 0;
         @(posedge clk);
      end

      done      = 1'b1; // Finished reading all data
      $fclose(data_file);
   end

   always @(posedge clk) begin
      if(count == 64)
         $display("Error: Invalid number of elements in the queue");
      if(deq && inp_data != out_data)
         $display("Error: Cycle %d, Count %d, Expected %d, Actual %d",
            cycle_num, count, inp_data, out_data);
   end

// Instantiate module under test
   pheap DUT (
      .clk(clk),
      .rst_n(rst_n),
      .enq (enq),
      .deq (deq),
      .inp_data({16'b0, inp_data}),
      .out_data(out_data),
      .full(),
      .empty(),
      .ready(),
      .elem_cnt(count)
   );

`ifdef PRIO_Q_DUMP_HEAP_CONTENTS
   integer               mem_file;  // memory dump file handler
   integer               p;

   initial begin // Open file for writing heap contents
      @(posedge rst_n);
      mem_file = $fopen("testbenches/mem_dump.dat", "w");
      if (mem_file == 0) begin
         $display("Error opening mem file");
         $finish;
      end

      @(posedge done); // After simulation completes
      $fclose(mem_file);
   end

   always @(posedge clk or negedge clk) begin : disp_routine
      if(rst_n && !done) begin
         $fwrite(mem_file,"%6d,",cycle_num);
         $fwrite(mem_file, "%3d,", DUT.L0);
         for(p = 0; p < 2; p = p+1) $fwrite(mem_file, "%3d,", DUT.L1[p]);
         for(p = 0; p < 4; p = p+1) $fwrite(mem_file, "%3d,", DUT.L2[p]);
         for(p = 0; p < 8; p = p+1) $fwrite(mem_file, "%3d,", DUT.L3[p]);
         for(p = 0; p < 16; p = p+1) $fwrite(mem_file, "%3d,", DUT.L4[p]);
         $fwrite(mem_file, "%3d,%3d,%3d,%3d,%3d\n",DUT.tmp1, DUT.tmp2, DUT.tmp3, DUT.tmp4, DUT.elem_cnt);
      end
   end
`endif

endmodule