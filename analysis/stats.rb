filename = "../verilog/sim.log"

## Checks:
# Queue has elements to dispatch
# Dispatched event is valid
# Event dispatched to unoccupied core
#
# GVT value is valid
#
# TODO: If events processing start in correct order in same LP

ARGV.each do |a|
   filename = a
end

NUM_CORE = 16
NUM_LP = 64
Q_SIZE = 62

qc = Array.new(Q_SIZE + 1, 0)
core_time = Array.new(NUM_CORE, -1)
core_lp = Array.new(NUM_CORE, -1)
gvt = 0

event_q = Array.new(NUM_LP){Array.new}
cancellation_q = Array.new(NUM_LP){Array.new}
rollback_q = Array.new(NUM_CORE){Array.new}

send_match = /[\s\d]+: (\w+?): ([\s\d]+)->([\s\d]+) to core ([\s\d]+)( \(C\)|) GVT: ([\s\d]+)/
recv_match  =/[\s\d]+: (\w+?): ([\s\d]+)->([\s\d]+) from core ([\s\d]+)(\(C\)|)/
recv_stat_match = /stall: ([\s\d]+), mem_rq: ([\s\d]+), memld: ([\s\d]+), memst: ([\s\d]+), total: ([\s\d]+)/
null_match = /null from core ([\s\d]+)/
exec_match = /[\s\d]+: exec: ([\s\d]+)->([\s\d]+) at core ([\s\d]+)(\(C\)|)/

cycle = 0

total = 0
cncl = 0
# Open and read file
File.foreach(filename) {|line|

   m = line.match(recv_match)
   if m != nil
      cncl = cncl + 1 if m[5].match("(C)") != nil

      m2 = line.match(/Q:(\d+)/)
      qt = m2[1].to_i
      qc[qt] = qc[qt] + 1
   end

   m = line.match(exec_match)
   if m != nil
      total = total + 1
   end
}

puts "Total processed = " + total.to_s
puts "Cancellation messages = " + cncl.to_s + " (#{'%.2f' % (cncl*100.0/total)}%)"
qc.each_index{|x|
   puts "#{x}: #{qc[x]}"
}
