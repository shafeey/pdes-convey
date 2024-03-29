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
   wire end_signal;
   reg r_end_signal;
   
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
   
   wire [NUM_CORE-1:0] set_new_active = (r_sent_msg_vld << r_core_id);
   wire [NUM_CORE-1:0] clear_finished = ~(r_rcv_msg_vld << r_core_id);
   
   always @(posedge clk) begin
      r_msg <= reset ? 0 : msg;
      r_sent_msg_vld <= reset ? 0 : sent_msg_vld;
      r_rcv_msg_vld <= reset ? 0 : (rcv_msg_vld && end_signal);
      r_core_id <= reset ? 0 : core_id;
      r_core_active <= reset ? 0 : ((r_core_active | set_new_active) & clear_finished);
      r_LP_id <= reset ? 0 : LP_id;
      r_event_time <= reset ? 0 : event_time;
      
      r_match <= reset ? 0 : match;
      r_hist_size <= reset ? 0 : hist_size;
      r_msg_LP_id <= reset ? 0 : core_LP_id[core_id];
      r_end_signal <= reset ? 0 : end_signal;
   end

   assign LP_id = msg[TIME_WID +: NB_LPID];
   assign event_time = msg[0 +: TIME_WID];
   assign hist_size = msg[MSG_WID-2:MSG_WID-NB_HIST_DEPTH-1];
   assign end_signal = msg[MSG_WID-1];
   
   assign stall = r_stall | c_stall;

//   reg [NB_LPID-1:0] r_cur_lp;
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
//         r_cur_lp <= core_LP_id[core_id];
         
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
      assign match_mask[m] = (1 << r_core_id); //(r_core_id == m);
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
//            r_match_send <= match_rcv;
            r_match_rcv <= match_rcv;
         end 
         else if(r_rcv_msg_vld) begin
            r_match_rcv <= match_rcv & ~(1 << r_core_id);
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
   reg [1:0] op [0:NB_COREID];
   reg [NB_COREID-1:0] core_id_his [0:NB_COREID];
   reg [NB_LPID-1:0] lp_id_his [0:NB_COREID];
      
   always @(posedge clk) begin : keep_hist
      integer q;
      for(q=0; q< NB_COREID; q = q+1) begin
         op[q] <= op[q+1];
         core_id_his[q] <= core_id_his[q+1];
         lp_id_his[q] <= lp_id_his[q+1];
      end
      op[NB_COREID] <= {r_sent_msg_vld, r_rcv_msg_vld};
      core_id_his[NB_COREID] <= r_core_id;
      lp_id_his[NB_COREID] <= core_LP_id[r_core_id];
   end
   
   
   reg [NUM_CORE-1:0] mask_set, mask_res;
   always @* begin
      c_stall = r_stall;
      mask_set = 0;
      mask_res = 0;
      
      if(sent_msg_vld) // Stall the core that's receiving new event
         mask_set = (1 << core_id);
      
      case (op[0])
      2'b01: begin //received event from core
         if(min_id_vld)
            mask_res = (1 <<  min_id);
      end
      2'b10: begin // sent event to core
         if(~min_id_vld)
            mask_res = (1 << core_id_his[0]);
      end
      default:
         mask_res = 0;
      endcase
         
//         c_stall[core_id] = 1;
//      else if(r_min_wait[1] && (|r_match_rcv) ) // Finding core with minimum timestamp finished (takes two cycle) 
         // Reset stall for core with smallest timestamp (if any)
//         c_stall[min_id] = 0;
//      else if(r_send_wait[1] && ~(|r_match_send) )
//         c_stall[r_mf_core_id] = 0;
   end
                        
   always @(posedge clk) begin
      r_stall <= reset ? 0 : ((c_stall | mask_set) & (~mask_res));
   end
   
   
   wire [NB_COREID-1:0] core_hist_update_target;
   assign core_hist_update_target = (op[0] == 2'b01) ? min_id : core_id_his[0];
   always @(posedge clk or posedge reset) begin
      if(reset) begin : reset_hist_size
         integer i;
         for(i=0; i<NUM_CORE; i=i+1) core_hist_size[i] <= 0;
      end 
      else begin
         if( op[0] == 2'b10 || ( op[0] == 2'b01 && min_id_vld) ) // sent event or (received event has stalling friend)
            core_hist_size[core_hist_update_target] <= LP_hist_size[lp_id_his[0]];
         
//         if(r_min_wait[1] && (|r_match_rcv) ) begin 
//            core_hist_size[min_id] <= LP_hist_size[r_mf_LP_id];
//         end
//         else if(r_send_wait[1]) begin
//            core_hist_size[r_mf_core_id] <= LP_hist_size[r_mf_LP_id];
//         end 
      end
   end
   
         
   /**
    * Find id of the core having minimum timestamp among cores with matching LP ID
    * Use binary reduction to find the smallest node
    */
    /*
   generate
      genvar i, j;
      
      for (j = 0; j < NB_COREID; j = j + 1) begin : m_id
         for(i = 0; i < 2**j; i = i+1) begin : cmp
            wire [TIME_WID-1:0]  left, right, min;
            reg [TIME_WID-1:0]  r_min;
            wire [NB_COREID-1:0]   left_idx, right_idx, min_idx;
            reg [NB_COREID-1:0]   r_min_idx;
            wire l_vld, r_vld, min_vld;
            reg r_min_vld;

            assign min = (l_vld && r_vld) ?
                              (left < right ? left : right) :
                              (l_vld ? left : right);
            assign min_idx = (l_vld && r_vld) ?
                              (left < right ? left_idx : right_idx) :
                              (l_vld ? left_idx : right_idx);
            assign min_vld = (l_vld || r_vld);

            if(j+1 == NB_COREID) begin
               assign l_vld = r_match_rcv[i*2];
               assign left = r_mf_core_times[i*2];
               assign left_idx = {i, 1'b0};
               assign r_vld = r_match_rcv[i*2 + 1];
               assign right = r_mf_core_times[i*2 + 1];
               assign right_idx = {i, 1'b1};
            end
            else begin
               assign l_vld = m_id[j+1].cmp[i*2].r_min_vld;
               assign left = m_id[j+1].cmp[i*2].r_min;
               assign left_idx = m_id[j+1].cmp[i*2].r_min_idx;
               assign r_vld = m_id[j+1].cmp[i*2 + 1].r_min_vld;
               assign right = m_id[j+1].cmp[i*2 + 1].r_min;
               assign right_idx = m_id[j+1].cmp[i*2 + 1].r_min_idx;
            end
            
            always @(posedge clk) begin
               r_min <= min;
               r_min_idx <= min_idx;
               r_min_vld <= min_vld;
            end
         end
      end

      assign min_id = m_id[0].cmp[0].r_min_idx;
      assign min_id_vld = m_id[0].cmp[0].r_min_vld;

   endgenerate
   
   */
   
   generate
      genvar i;
      
      wire [TIME_WID-1:0]  cmp6_min[0:63];
      wire [NB_COREID-1:0]   cmp6_min_idx[0:63];
      wire cmp6_min_vld[0:63];
      
            // Level 5
      wire [TIME_WID-1:0]  cmp5_min[0:31];
      wire [NB_COREID-1:0]   cmp5_min_idx[0:31];
      wire cmp5_min_vld[0:31];
      
      for(i = 0; i < 32; i = i+1) begin : cmp5
         wire [TIME_WID-1:0]  left, right, min;
         reg [TIME_WID-1:0]  r_min;
         wire [NB_COREID-1:0]   left_idx, right_idx, min_idx;
         reg [NB_COREID-1:0]   r_min_idx;
         wire l_vld, r_vld, min_vld;
         reg r_min_vld;

         assign min = (l_vld && r_vld) ?
                           (left < right ? left : right) :
                           (l_vld ? left : right);
         assign min_idx = (l_vld && r_vld) ?
                           (left < right ? left_idx : right_idx) :
                           (l_vld ? left_idx : right_idx);
         assign min_vld = (l_vld || r_vld);

         if(6 == NB_COREID) begin
           /* Top level, assign from input signals */
            assign l_vld = r_match_rcv[i*2];
            assign left = r_mf_core_times[i*2];
            assign left_idx = {i, 1'b0};
            assign r_vld = r_match_rcv[i*2 + 1];
            assign right = r_mf_core_times[i*2 + 1];
            assign right_idx = {i, 1'b1};
         end
         else begin
            assign l_vld = cmp6_min_vld[i*2];
            assign left = cmp6_min[i*2];
            assign left_idx = cmp6_min_idx[i*2];
            assign r_vld = cmp6_min_vld[i*2 + 1];
            assign right = cmp6_min[i*2 + 1];
            assign right_idx = cmp6_min_idx[i*2 + 1];
         end
            
         always @(posedge clk) begin
            r_min <= min;
            r_min_idx <= min_idx;
            r_min_vld <= min_vld;
         end
            
         assign cmp5_min[i] = r_min;
         assign cmp5_min_idx[i] = r_min_idx;
         assign cmp5_min_vld[i] = r_min_vld;
      end  
      
            // Level 4
      wire [TIME_WID-1:0]  cmp4_min[0:15];
      wire [NB_COREID-1:0]   cmp4_min_idx[0:15];
      wire cmp4_min_vld[0:15];
      
      for(i = 0; i < 16; i = i+1) begin : cmp4
         wire [TIME_WID-1:0]  left, right, min;
         reg [TIME_WID-1:0]  r_min;
         wire [NB_COREID-1:0]   left_idx, right_idx, min_idx;
         reg [NB_COREID-1:0]   r_min_idx;
         wire l_vld, r_vld, min_vld;
         reg r_min_vld;

         assign min = (l_vld && r_vld) ?
                           (left < right ? left : right) :
                           (l_vld ? left : right);
         assign min_idx = (l_vld && r_vld) ?
                           (left < right ? left_idx : right_idx) :
                           (l_vld ? left_idx : right_idx);
         assign min_vld = (l_vld || r_vld);

         if(5 == NB_COREID) begin
           /* Top level, assign from input signals */
            assign l_vld = r_match_rcv[i*2];
            assign left = r_mf_core_times[i*2];
            assign left_idx = {i, 1'b0};
            assign r_vld = r_match_rcv[i*2 + 1];
            assign right = r_mf_core_times[i*2 + 1];
            assign right_idx = {i, 1'b1};
         end
         else begin
            assign l_vld = cmp5_min_vld[i*2];
            assign left = cmp5_min[i*2];
            assign left_idx = cmp5_min_idx[i*2];
            assign r_vld = cmp5_min_vld[i*2 + 1];
            assign right = cmp5_min[i*2 + 1];
            assign right_idx = cmp5_min_idx[i*2 + 1];
         end
            
         always @(posedge clk) begin
            r_min <= min;
            r_min_idx <= min_idx;
            r_min_vld <= min_vld;
         end
            
         assign cmp4_min[i] = r_min;
         assign cmp4_min_idx[i] = r_min_idx;
         assign cmp4_min_vld[i] = r_min_vld;
      end  
      
      // Level 3
      wire [TIME_WID-1:0]  cmp3_min[0:7];
      wire [NB_COREID-1:0]   cmp3_min_idx[0:7];
      wire cmp3_min_vld[0:7];
      
      for(i = 0; i < 8; i = i+1) begin : cmp3
         wire [TIME_WID-1:0]  left, right, min;
         reg [TIME_WID-1:0]  r_min;
         wire [NB_COREID-1:0]   left_idx, right_idx, min_idx;
         reg [NB_COREID-1:0]   r_min_idx;
         wire l_vld, r_vld, min_vld;
         reg r_min_vld;

         assign min = (l_vld && r_vld) ?
                           (left < right ? left : right) :
                           (l_vld ? left : right);
         assign min_idx = (l_vld && r_vld) ?
                           (left < right ? left_idx : right_idx) :
                           (l_vld ? left_idx : right_idx);
         assign min_vld = (l_vld || r_vld);

         if(4 == NB_COREID) begin
           /* Top level, assign from input signals */
            assign l_vld = r_match_rcv[i*2];
            assign left = r_mf_core_times[i*2];
            assign left_idx = {i, 1'b0};
            assign r_vld = r_match_rcv[i*2 + 1];
            assign right = r_mf_core_times[i*2 + 1];
            assign right_idx = {i, 1'b1};
         end
         else begin
            assign l_vld = cmp4_min_vld[i*2];
            assign left = cmp4_min[i*2];
            assign left_idx = cmp4_min_idx[i*2];
            assign r_vld = cmp4_min_vld[i*2 + 1];
            assign right = cmp4_min[i*2 + 1];
            assign right_idx = cmp4_min_idx[i*2 + 1];
         end
            
         always @(posedge clk) begin
            r_min <= min;
            r_min_idx <= min_idx;
            r_min_vld <= min_vld;
         end
            
         assign cmp3_min[i] = r_min;
         assign cmp3_min_idx[i] = r_min_idx;
         assign cmp3_min_vld[i] = r_min_vld;
      end  
      
      // Level 2
      wire [TIME_WID-1:0]  cmp2_min[0:3];
      wire [NB_COREID-1:0]   cmp2_min_idx[0:3];
      wire cmp2_min_vld[0:3];
      
      for(i = 0; i < 4; i = i+1) begin : cmp2
         wire [TIME_WID-1:0]  left, right, min;
         reg [TIME_WID-1:0]  r_min;
         wire [NB_COREID-1:0]   left_idx, right_idx, min_idx;
         reg [NB_COREID-1:0]   r_min_idx;
         wire l_vld, r_vld, min_vld;
         reg r_min_vld;

         assign min = (l_vld && r_vld) ?
                           (left < right ? left : right) :
                           (l_vld ? left : right);
         assign min_idx = (l_vld && r_vld) ?
                           (left < right ? left_idx : right_idx) :
                           (l_vld ? left_idx : right_idx);
         assign min_vld = (l_vld || r_vld);

         if(3 == NB_COREID) begin
           /* Top level, assign from input signals */
            assign l_vld = r_match_rcv[i*2];
            assign left = r_mf_core_times[i*2];
            assign left_idx = {i, 1'b0};
            assign r_vld = r_match_rcv[i*2 + 1];
            assign right = r_mf_core_times[i*2 + 1];
            assign right_idx = {i, 1'b1};
         end
         else begin
            assign l_vld = cmp3_min_vld[i*2];
            assign left = cmp3_min[i*2];
            assign left_idx = cmp3_min_idx[i*2];
            assign r_vld = cmp3_min_vld[i*2 + 1];
            assign right = cmp3_min[i*2 + 1];
            assign right_idx = cmp3_min_idx[i*2 + 1];
         end
            
         always @(posedge clk) begin
            r_min <= min;
            r_min_idx <= min_idx;
            r_min_vld <= min_vld;
         end
            
         assign cmp2_min[i] = r_min;
         assign cmp2_min_idx[i] = r_min_idx;
         assign cmp2_min_vld[i] = r_min_vld;
      end      
      
      // Level 1
      wire [TIME_WID-1:0]  cmp1_min[0:1];
      wire [NB_COREID-1:0]   cmp1_min_idx[0:1];
      wire cmp1_min_vld[0:1];
      
      for(i = 0; i < 2; i = i+1) begin : cmp1
         wire [TIME_WID-1:0]  left, right, min;
         reg [TIME_WID-1:0]  r_min;
         wire [NB_COREID-1:0]   left_idx, right_idx, min_idx;
         reg [NB_COREID-1:0]   r_min_idx;
         wire l_vld, r_vld, min_vld;
         reg r_min_vld;

         assign min = (l_vld && r_vld) ?
                           (left < right ? left : right) :
                           (l_vld ? left : right);
         assign min_idx = (l_vld && r_vld) ?
                           (left < right ? left_idx : right_idx) :
                           (l_vld ? left_idx : right_idx);
         assign min_vld = (l_vld || r_vld);

         if(2 == NB_COREID) begin
           /* Top level, assign from input signals */
            assign l_vld = r_match_rcv[i*2];
            assign left = r_mf_core_times[i*2];
            assign left_idx = {i, 1'b0};
            assign r_vld = r_match_rcv[i*2 + 1];
            assign right = r_mf_core_times[i*2 + 1];
            assign right_idx = {i, 1'b1};
         end
         else begin
            assign l_vld = cmp2_min_vld[i*2];
            assign left = cmp2_min[i*2];
            assign left_idx = cmp2_min_idx[i*2];
            assign r_vld = cmp2_min_vld[i*2 + 1];
            assign right = cmp2_min[i*2 + 1];
            assign right_idx = cmp2_min_idx[i*2 + 1];
         end
            
         always @(posedge clk) begin
            r_min <= min;
            r_min_idx <= min_idx;
            r_min_vld <= min_vld;
         end
            
         assign cmp1_min[i] = r_min;
         assign cmp1_min_idx[i] = r_min_idx;
         assign cmp1_min_vld[i] = r_min_vld;
      end
      
      // Level 0
      wire [TIME_WID-1:0]  cmp0_min[0:0];
      wire [NB_COREID-1:0]   cmp0_min_idx[0:0];
      wire cmp0_min_vld[0:0];
      
      for(i = 0; i < 1; i = i+1) begin : cmp0
         wire [TIME_WID-1:0]  left, right, min;
         reg [TIME_WID-1:0]  r_min;
         wire [NB_COREID-1:0]   left_idx, right_idx, min_idx;
         reg [NB_COREID-1:0]   r_min_idx;
         wire l_vld, r_vld, min_vld;
         reg r_min_vld;

         assign min = (l_vld && r_vld) ?
                           (left < right ? left : right) :
                           (l_vld ? left : right);
         assign min_idx = (l_vld && r_vld) ?
                           (left < right ? left_idx : right_idx) :
                           (l_vld ? left_idx : right_idx);
         assign min_vld = (l_vld || r_vld);

         if(1 == NB_COREID) begin
           /* Top level, assign from input signals */
            assign l_vld = r_match_rcv[i*2];
            assign left = r_mf_core_times[i*2];
            assign left_idx = {i, 1'b0};
            assign r_vld = r_match_rcv[i*2 + 1];
            assign right = r_mf_core_times[i*2 + 1];
            assign right_idx = {i, 1'b1};
         end
         else begin
            assign l_vld = cmp1_min_vld[i*2];
            assign left = cmp1_min[i*2];
            assign left_idx = cmp1_min_idx[i*2];
            assign r_vld = cmp1_min_vld[i*2 + 1];
            assign right = cmp1_min[i*2 + 1];
            assign right_idx = cmp1_min_idx[i*2 + 1];
         end
            
         always @(posedge clk) begin
            r_min <= min;
            r_min_idx <= min_idx;
            r_min_vld <= min_vld;
         end
            
         assign cmp0_min[i] = r_min;
         assign cmp0_min_idx[i] = r_min_idx;
         assign cmp0_min_vld[i] = r_min_vld;
      end
      
      assign min_id = cmp0_min_idx[0];
      assign min_id_vld = cmp0_min_vld[0];
      
   endgenerate

      
   /**
    * Find the minimum timestamp among the active cores
    */
    
    wire [TIME_WID-1:0] min_core_times[0:(NUM_CORE >> 3)-1];
   wire min_core_vld;
    wire [TIME_WID-1:0] mt0, mt1, mt2, mt3, mt4, mt5, mt6, mt;
    
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
       
       reg [(NUM_CORE >> 3)-1:0] v1, v2;
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
       
       if(NUM_CORE == 8) begin
          assign min_time = min_core_times[0];
       end
       else if(NUM_CORE == 16) begin
          assign mt0 = (min_core_times[0] < min_core_times[1]) ? min_core_times[0] : min_core_times[1];
          assign min_time = mt0;
       end 
       else if(NUM_CORE == 32) begin
          assign mt0 = (min_core_times[0] < min_core_times[1]) ? min_core_times[0] : min_core_times[1];
          assign mt1 = (min_core_times[2] < min_core_times[3]) ? min_core_times[2] : min_core_times[3];
          
          assign mt2 = (mt0 < mt1) ? mt0 : mt1;
          assign mt = min_core_vld ? mt2 : 0;
          
          assign min_time = mt;
       end
       else if(NUM_CORE == 64) begin
          assign mt0 = (min_core_times[0] < min_core_times[1]) ? min_core_times[0] : min_core_times[1];
          assign mt1 = (min_core_times[2] < min_core_times[3]) ? min_core_times[2] : min_core_times[3];
          
          assign mt2 = (min_core_times[4] < min_core_times[5]) ? min_core_times[4] : min_core_times[5];
          assign mt3 = (min_core_times[6] < min_core_times[7]) ? min_core_times[6] : min_core_times[7];
          
          assign mt4 = (mt0 < mt1) ? mt0 : mt1;
          assign mt5 = (mt2 < mt3) ? mt2 : mt3;
          assign mt6 = (mt4 < mt5) ? mt4 : mt5;
          assign mt = min_core_vld ? mt6 : 0;
          
//          assign min_time = mt;
       end
       
      
    endgenerate
    
    reg [TIME_WID-1:0] r_min_time;
    reg r_min_time_vld;
    always @(posedge clk) begin
       r_min_time <= mt;
       r_min_time_vld <= (min_time_ctr == 9);
    end
    assign min_time = r_min_time;
    assign min_time_vld = r_min_time_vld;
    
    
    reg [TIME_WID-1:0] min_msg_time;
    always @(posedge clk) begin
       if(reset || min_time_vld)
          min_msg_time <= {TIME_WID{1'b1}};
       else
          if(sent_msg_vld || (rcv_msg_vld && end_signal)) begin
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
//    
//    assign mt0 = (min_core_times[0] < min_core_times[1]) ? min_core_times[0] : min_core_times[1];
//    assign mt1 = (min_core_times[2] < min_core_times[3]) ? min_core_times[2] : min_core_times[3];
//    
//    assign mt2 = (mt0 < mt1) ? mt0 : mt1;
//    assign mt = min_core_vld ? mt2 : 0;
//    
//    assign min_time = mt < min_msg_time ? mt : min_msg_time;
//    assign min_time_vld = (min_time_ctr == 9);
    

endmodule
