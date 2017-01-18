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
      input  [NB_COREID-1:0]  core_id,
      output [NUM_CORE-1:0] stall,        // Stall signals for the cores
      
      output [TIME_WID-1:0]   min_time,     // Smallest timestamp within active cores
      output                min_time_vld,
      
      output [NB_HIST_DEPTH*NUM_CORE-1:0]          core_hist_cnt,
      input [NUM_CORE-1:0] core_active,

      input                 reset
   );


   reg    [TIME_WID-1:0] core_times [0:NUM_CORE-1];
   reg    [NB_LPID-1:0]    core_LP_id [0:NUM_CORE-1];
   
   reg    [NUM_CORE-1:0] r_stall;
   reg    [NUM_CORE-1:0] c_stall;

   wire   [TIME_WID-1:0] event_time;

   wire   [NB_LPID-1:0]    LP_id;
   reg    [NB_LPID-1:0]    r_LP_id;
   
   wire   [NB_COREID-1:0]  min_id;
   wire                  min_id_vld;
   wire   [NUM_CORE-1:0] match;
   wire   [NUM_CORE-1:0] match_rcv; // Match LP id in other cores when receiving events
   wire   [NUM_CORE-1:0] match_mask;
   
   reg    [NB_HIST_DEPTH-1:0] LP_hist_size[0:NUM_LP-1];
   reg    [NB_HIST_DEPTH-1:0] core_hist_size[0:NUM_CORE-1];
   wire   [NB_HIST_DEPTH-1:0] hist_size;
   
   genvar p;
   for(p=0; p<NUM_CORE; p = p+1) begin : expand_bus
       assign core_hist_cnt[p*NB_HIST_DEPTH +: NB_HIST_DEPTH] = core_hist_size[p];
   end
   
   reg [MSG_WID-1:0] r_msg;
   reg r_sent_msg_vld, r_rcv_msg_vld;
   reg [NB_COREID-1:0] r_core_id;
   reg [NUM_CORE-1:0] r_core_active;
   reg [TIME_WID-1:0] r_event_time;
   reg [NUM_CORE-1:0] r_match, r_match_rcv, r_match_send;
   reg [NB_HIST_DEPTH-1:0] r_hist_size;
   reg [NB_LPID-1:0] r_msg_LP_id;
   
   reg    [TIME_WID-1:0] r_mf_core_times [0:NUM_CORE-1];
   reg    [NB_LPID-1:0]    r_mf_LP_id;
   reg [NB_COREID-1:0] r_mf_core_id;
   
   always @(posedge clk) begin
      r_msg <= reset ? 0 : msg;
      r_sent_msg_vld <= reset ? 0 : sent_msg_vld;
      r_rcv_msg_vld <= reset ? 0 : rcv_msg_vld;
      r_core_id <= reset ? 0 : core_id;
      r_core_active <= reset ? 0 : core_active;
      r_LP_id <= reset ? 0 : LP_id;
      r_event_time <= reset ? 0 : event_time;
      
      r_match <= reset ? 0 : match;
      r_hist_size <= reset ? 0 : hist_size;
      r_msg_LP_id <= reset ? 0 : core_LP_id[core_id];
   end

   assign LP_id = msg[TIME_WID +: NB_LPID];
   assign event_time = msg[0 +: TIME_WID];
   assign hist_size = msg[MSG_WID-1:MSG_WID-NB_HIST_DEPTH];
   
   assign stall = r_stall | c_stall;

   always @(posedge clk) begin 
      if(reset) begin : reset_table
         integer i;
         for(i = 0; i < NUM_CORE; i= i+1) begin
            core_times[i] <= 0;
            core_LP_id[i] <= 0;
         end
         for(i=0; i<NUM_LP; i=i+1) LP_hist_size[i] <= 0;
      end
      else begin
         if(sent_msg_vld) begin
            core_times[core_id] <= event_time;
            core_LP_id[core_id] <= LP_id;
         end
         if(r_rcv_msg_vld) begin
            LP_hist_size[core_LP_id[r_core_id]] <= r_hist_size;
         end 
      end
   end

   genvar m;
   /**
    * Compare the LP id with all the ACTIVE cores' LP and set the match bit
    * Exclude the core that is receiving the event 
    */
   for(m=0; m<NUM_CORE; m=m+1) begin : mtc
      assign match[m] = (r_core_active[m] && core_LP_id[m] == r_LP_id && core_id != m);
   end
   
   /**
    * Compare the LP id of the core that's returning an event with the LP id of
    * other active cores and set match bit. Exclude the core that is returning. 
    */
   for(m=0; m<NUM_CORE; m=m+1) begin : mtc_min
      assign match_rcv[m] = (r_core_active[m] && core_LP_id[m] == core_LP_id[r_core_id]);
      assign match_mask[m] = (r_core_id == m);
   end
   
   reg [1:0] r_min_wait;
   reg [1:0] r_send_wait;
   
   always @(posedge clk) begin
      if(reset) begin
         r_match_rcv <= 0;
         r_match_send <= 0;
         r_min_wait <= 0;
         r_mf_LP_id <= 0;
         r_mf_core_id <= 0;
      end
      else begin
         r_min_wait <= (r_min_wait[1] && sent_msg_vld) ? r_min_wait : {r_min_wait[0], r_rcv_msg_vld};
         r_send_wait <= (r_send_wait[1] && sent_msg_vld) ? r_send_wait :  {r_send_wait[0], r_sent_msg_vld};
         r_mf_LP_id <= (r_rcv_msg_vld || r_sent_msg_vld) ? core_LP_id[r_core_id] : r_mf_LP_id;
         r_mf_core_id <= r_sent_msg_vld || r_rcv_msg_vld ? r_core_id : r_mf_core_id;
         
         if(r_sent_msg_vld) begin
            r_match_send <= match_rcv;
         end 
         
         if(r_rcv_msg_vld) begin
            r_match_rcv <= match_rcv ^ match_mask;
         end
         
         
         if (r_rcv_msg_vld) begin : mf
            integer i;
            for(i=0; i<NUM_CORE; i=i+1) r_mf_core_times[i] <= core_times[i];
            // Find the cores processing the msg's LP_id and 
            // If the core received new event, it's not marked active yet. XOR includes this in the minimum finding process
            // If the core is sending messages, it's already marked active but it should be ignored to find the next eligible core.
            // XOR operation removes it from the minimum finding process.
         end
      end
   end
   

   // Stall signal generation
   always @* begin
      c_stall = r_stall;
      if(sent_msg_vld) // Stall the core that's receiving new event
         c_stall[core_id] = 1;
      else if(r_min_wait[1] && (|r_match_rcv) ) // Finding core with minimum timestamp finished (takes two cycle) 
         // Reset stall for core with smallest timestamp (if any)
         c_stall[min_id] = 0;
      else if(r_send_wait[1] && ~(|r_match_send) )
         c_stall[r_mf_core_id] = 0;
   end
                        
   always @(posedge clk) begin
      r_stall <= reset ? 0 : c_stall;
   end
   
   
   always @(posedge clk or posedge reset) begin
      if(reset) begin : reset_hist_size
         integer i;
         for(i=0; i<NUM_CORE; i=i+1) core_hist_size[i] <= 0;
      end 
      else begin
         if(r_min_wait[1] && (|r_match_rcv) ) begin 
            core_hist_size[min_id] <= LP_hist_size[r_mf_LP_id];
         end
         else if(r_send_wait[1]) begin
            core_hist_size[r_mf_core_id] <= LP_hist_size[r_mf_LP_id];
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
               assign l_vld = r_match_rcv[i*2];
               assign left = r_mf_core_times[i*2];
               assign left_idx = {i, 1'b0};
               assign r_vld = r_match_rcv[i*2 + 1];
               assign right = r_mf_core_times[i*2 + 1];
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
    
    wire [TIME_WID-1:0] min_core_times[0:3];
   wire min_core_vld;
    
    reg [3:0] min_time_ctr;
    generate
      genvar g, h;
//      for (h = 0; h < NB_COREID; h = h + 1) begin : m_time
//         for(g = 0; g < 2**h; g = g+1) begin : cmp
//            wire [TIME_WID-1:0]  left, right, min;
//            wire                 l_vld, r_vld, min_vld;
//
//            assign min = (l_vld && r_vld) ?
//                              (left < right ? left : right) :
//                              (l_vld ? left : right);
//            assign min_vld = (l_vld || r_vld);
//
//            if(h+1 == NB_COREID) begin
//               /* Top level, assign from input signals */
//               assign l_vld = core_active[g*2];
//               assign left = core_times[g*2];
//               assign r_vld = core_active[g*2 + 1];
//               assign right = core_times[g*2 + 1];
//            end
//            else begin
//               assign l_vld = m_time[h+1].cmp[g*2].min_vld;
//               assign left = m_time[h+1].cmp[g*2].min;
//               assign r_vld = m_time[h+1].cmp[g*2 + 1].min_vld;
//               assign right = m_time[h+1].cmp[g*2 + 1].min;
//            end
//         end
//      end
//
//      assign min_time = m_time[0].cmp[0].min;
//      assign min_time_vld = m_time[0].cmp[0].min_vld;
       
       reg [3:0] v1, v2;
       for(g=0; g < (NUM_CORE >> 3); g = g+1) begin : min_vt
          reg [TIME_WID-1:0] min_core_time1, min_core_time2; 
          wire [TIME_WID-1:0] core_time;
          
          assign core_time = core_times[{g,min_time_ctr[0 +: 3]}];
          
          always @(posedge clk) begin
             if(reset) begin
                min_core_time1 <= {TIME_WID{1'b1}};
                min_core_time2 <= {TIME_WID{1'b1}};
                v1[g] <= 0;
                v2[g] <= 0;
             end
             else begin
                if(min_time_ctr == 9) begin
                   min_core_time1 <= {TIME_WID{1'b1}};
                   min_core_time2 <= min_core_time1;
                   v1[g] <= 0;
                   v2[g] <= v1[g];
                end
                else begin
                   if( r_core_active[ {g,min_time_ctr[0 +: 3]} ] ) begin
                      if(min_core_time1 > core_time)
                        min_core_time1 <= core_time;
                      if(min_core_time2 > core_time)
                         min_core_time2 <= core_time;
                      v1[g] <= 1;
                      v2[g] <= 1;
                   end
                end
             end
          end
          
          assign min_core_times[g] = min_core_time2;
          assign min_core_vld = |v2;
          
       end
      
    endgenerate
    
    reg [TIME_WID-1:0] min_msg_time;
    always @(posedge clk) begin
       if(reset || min_time_vld)
          min_msg_time <= {TIME_WID{1'b1}};
       else
          if(sent_msg_vld || rcv_msg_vld) begin
             min_msg_time <= min_msg_time < event_time ? min_msg_time : event_time;
          end
    end
    
    
    always @(posedge clk) begin
       if(reset)
          min_time_ctr <= 0;
       else if(min_time_ctr == 9)
          min_time_ctr <= 0;
       else
          min_time_ctr <= min_time_ctr + 1;
    end
    
    wire [TIME_WID-1:0] mt0, mt1, mt2, mt;
    assign mt0 = (min_core_times[0] < min_core_times[1]) ? min_core_times[0] : min_core_times[1];
    assign mt1 = (min_core_times[2] < min_core_times[3]) ? min_core_times[2] : min_core_times[3];
    
    assign mt2 = (mt0 < mt1) ? mt0 : mt1;
    assign mt = min_core_vld ? mt2 : 0;
    
    assign min_time = mt < min_msg_time ? mt : min_msg_time;
    assign min_time_vld = (min_time_ctr == 9);
    

endmodule
