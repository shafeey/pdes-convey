module gvt_monitor #(
      parameter NUM_CORE = 4,
      parameter TIME_WID = 16
   )(
      input  [TIME_WID*NUM_CORE-1:0]    core_times,
      input  [NUM_CORE-1:0]             core_vld,
      input  [TIME_WID-1:0]             next_event,
      output [TIME_WID-1:0]             gvt
   );

   generate
      genvar i, j;
      for (j = 0; j < $clog2(NUM_CORE); j = j + 1) begin : gen_levels
         for(i = 0; i < 2**j; i = i+1) begin : cmp
            wire [TIME_WID-1:0]  left, right, min;
            wire                 l_vld, r_vld, min_vld;

            assign min = (l_vld && r_vld) ?
                              (left < right ? left : right) :
                              (l_vld ? left : right);
            assign min_vld = (l_vld || r_vld);

            if(j+1 == $clog2(NUM_CORE)) begin
               /* Top level, assign from input signals */
               assign l_vld = core_vld[i*2];
               assign left = core_times[TIME_WID*i*2 +: TIME_WID];
               assign r_vld = core_vld[i*2 + 1];
               assign right = core_times[TIME_WID*i*2 + TIME_WID +: TIME_WID];
            end
            else begin
               assign l_vld = gen_levels[j+1].cmp[i*2].min_vld;
               assign left = gen_levels[j+1].cmp[i*2].min;
               assign r_vld = gen_levels[j+1].cmp[i*2 + 1].min_vld;
               assign right = gen_levels[j+1].cmp[i*2 + 1].min;
            end
         end
      end

      assign gvt = gen_levels[0].cmp[0].min_vld ?
                        (gen_levels[0].cmp[0].min < next_event ? gen_levels[0].cmp[0].min : next_event) :
                        next_event;
   endgenerate


endmodule

