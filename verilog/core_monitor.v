/**
 * Monitors the current LP being processed in all cores and stalls conflicting cores
 * 
 * Module monitors all data being passed from and to the cores and keep a table listing
 * the LP and timestamp of each core. 
 * When a new message is dequeued from the queue-
 * - Update the table entries and mark the core active
 * - Check if the LP of the new event is already in other core
 * - - Yes: set stall = 1 for the destination core.
 * - - No; keep stall = 0
 * When a message arrives from the cores
 * - Mark the core inactive
 * - Set stall = 0 for the originating core
 * - Check if the LP exists in any other active core
 * - - Yes: set stall = 0 for the core having the same LP and smallest timestamp
 */
module core_monitor #(
      parameter NUM_CORE = 4,
      parameter NB_COREID = $clog2(NUM_CORE),
      parameter NUM_LP = 8,
      parameter NB_LPID =   $clog2(NUM_LP),
      parameter TIME_WID = 16,
      parameter MSG_WID = 32,
      parameter NB_HIST_DEPTH = 4
   )(
      input                 clk,
      input  [MSG_WID-1:0]  msg,          // Message to/from the cores
      input                 sent_msg_vld, // Message sent from queue to cores
      input                 rcv_msg_vld,  // Message sent from cores to queue
      input  [$clog2(NUM_CORE)-1:0]  core_id,
      output [NUM_CORE-1:0] stall,        // Stall signals for the cores
      
      output [TIME_WID-1:0]   min_time,     // Smallest timestamp within active cores
      output                min_time_vld,
      
      output [4*NUM_CORE-1:0]          core_hist_cnt,
      input [NUM_CORE-1:0] core_active,

      input                 reset
   );


   reg    [TIME_WID-1:0] core_times [0:NUM_CORE-1];
   reg    [NB_LPID-1:0]    core_LP_id [0:NUM_CORE-1];
   
   reg    [NUM_CORE-1:0] r_stall;
   reg    [NUM_CORE-1:0] c_stall;

   wire   [TIME_WID-1:0] event_time;

   wire   [NB_LPID-1:0]    LP_id;
   wire   [NB_COREID-1:0]  min_id;
   wire                  min_id_vld;
   wire   [NUM_CORE-1:0] match;
   wire   [NUM_CORE-1:0] match_rcv; // Match LP id in other cores when receiving events
   
   reg    [NB_HIST_DEPTH-1:0] LP_hist_size[0:NUM_LP-1];
   reg    [NB_HIST_DEPTH-1:0] core_hist_size[0:NUM_CORE-1];
   wire   [NB_HIST_DEPTH-1:0] hist_size;
   
   genvar p;
   for(p=0; p<NUM_CORE; p = p+1) begin : expand_bus
       assign core_hist_cnt[p*NB_HIST_DEPTH +: NB_HIST_DEPTH] = core_hist_size[p];
   end

   assign LP_id = msg[TIME_WID +: NB_LPID];
   assign event_time = msg[0 +: TIME_WID];
   
   assign stall = r_stall | c_stall;

   always @(posedge clk) begin 
      if(reset) begin : reset_table
         integer i;
         for(i = 0; i < NUM_CORE; i= i+1) begin
            core_times[i] <= 0;
            core_LP_id[i] <= 0;
         end
      end
      else begin
         if(sent_msg_vld) begin
            core_times[core_id] <= event_time;
            core_LP_id[core_id] <= LP_id;
         end
      end
   end

   /**
    * Compare the LP id with all the ACTIVE cores' LP and set the match bit
    * Exclude the core that is receiving the event 
    */
   genvar m;
   for(m=0; m<NUM_CORE; m=m+1) begin : mtc
      assign match[m] = (core_active[m] && core_LP_id[m] == LP_id && core_id != m);
   end
   
   /**
    * Compare the LP id of the core that's returning an event with the LP id of
    * other active cores and set match bit. Exclude the core that is returning. 
    */
   for(m=0; m<NUM_CORE; m=m+1) begin : mtc_min
      assign match_rcv[m] = (core_active[m] && core_LP_id[m] == core_LP_id[core_id] && core_id != m);
   end

   // Stall signal generation
   always @* begin
      c_stall = r_stall;
      if(sent_msg_vld && (|match)) // same LP exists in another core, stall
         c_stall[core_id] = 1;
      else if(rcv_msg_vld && min_id_vld) 
         // Reset stall for core with smallest timestamp (if any)
         c_stall[min_id] = 0;
   end
                        
   always @(posedge clk) begin
      r_stall <= reset ? 0 : c_stall;
   end
   
   
   assign hist_size = msg[MSG_WID-1:MSG_WID-NB_HIST_DEPTH];
   always @(posedge clk or posedge reset) begin
      if(reset) begin : reset_hist_size
         integer i;
         for(i=0; i<NUM_LP; i=i+1) LP_hist_size[i] <= 0;
         for(i=0; i<NUM_CORE; i=i+1) core_hist_size[i] <= 0;
      end 
      else begin
         if(sent_msg_vld) begin
            core_hist_size[core_id] <= LP_hist_size[LP_id];
         end
         else 
            if(rcv_msg_vld) begin 
               LP_hist_size[core_LP_id[core_id]] <= hist_size;
               if(min_id_vld) begin 
                  core_hist_size[min_id] <= hist_size;
               end
            end
      end
   end
   
         
   /**
    * Find id of the core having minimum timestamp among cores with matching LP ID
    * Use binary reduction to find the smallest node
    */
   generate
      genvar i, j;
      for (j = 0; j < NB_COREID; j = j + 1) begin : m_id
         for(i = 0; i < 2**j; i = i+1) begin : cmp
            wire [TIME_WID-1:0]  left, right, min;
            wire [NB_COREID-1:0]   left_idx, right_idx, min_idx;
            wire                 l_vld, r_vld, min_vld;

            assign min = (l_vld && r_vld) ?
                              (left < right ? left : right) :
                              (l_vld ? left : right);
            assign min_idx = (l_vld && r_vld) ?
                              (left < right ? left_idx : right_idx) :
                              (l_vld ? left_idx : right_idx);
            assign min_vld = (l_vld || r_vld);

            if(j+1 == NB_COREID) begin
               /* Top level, assign from input signals */
               assign l_vld = match_rcv[i*2];
               assign left = core_times[i*2];
               assign left_idx = {i, 1'b0};
               assign r_vld = match_rcv[i*2 + 1];
               assign right = core_times[i*2 + 1];
               assign right_idx = {i, 1'b1};
            end
            else begin
               assign l_vld = m_id[j+1].cmp[i*2].min_vld;
               assign left = m_id[j+1].cmp[i*2].min;
               assign left_idx = m_id[j+1].cmp[i*2].min_idx;
               assign r_vld = m_id[j+1].cmp[i*2 + 1].min_vld;
               assign right = m_id[j+1].cmp[i*2 + 1].min;
               assign right_idx = m_id[j+1].cmp[i*2 + 1].min_idx;
            end
         end
      end

      assign min_id = m_id[0].cmp[0].min_idx;
      assign min_id_vld = m_id[0].cmp[0].min_vld;

   endgenerate
   
   /**
    * Find the minimum timestamp among the active cores
    */
    generate
      genvar g, h;
      for (h = 0; h < NB_COREID; h = h + 1) begin : m_time
         for(g = 0; g < 2**h; g = g+1) begin : cmp
            wire [TIME_WID-1:0]  left, right, min;
            wire                 l_vld, r_vld, min_vld;

            assign min = (l_vld && r_vld) ?
                              (left < right ? left : right) :
                              (l_vld ? left : right);
            assign min_vld = (l_vld || r_vld);

            if(h+1 == NB_COREID) begin
               /* Top level, assign from input signals */
               assign l_vld = core_active[g*2];
               assign left = core_times[g*2];
               assign r_vld = core_active[g*2 + 1];
               assign right = core_times[g*2 + 1];
            end
            else begin
               assign l_vld = m_time[h+1].cmp[g*2].min_vld;
               assign left = m_time[h+1].cmp[g*2].min;
               assign r_vld = m_time[h+1].cmp[g*2 + 1].min_vld;
               assign right = m_time[h+1].cmp[g*2 + 1].min;
            end
         end
      end

      assign min_time = m_time[0].cmp[0].min;
      assign min_time_vld = m_time[0].cmp[0].min_vld;

   endgenerate
   
endmodule
