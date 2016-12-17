filename = "../verilog/sim.txt"

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

class PriorityQueue
    attr_reader :elements

    def initialize
	@elements = [nil]
    end

    def <<(element)
	@elements << element
	bubble_up(@elements.size - 1)
    end

    def pop
	exchange(1, @elements.size - 1)
	max = @elements.pop
	bubble_down(1)
	max
    end

    def peek
       @elements[1]
    end

    def size
       @elements.size-1
    end

    private

    def bubble_up(index)
	parent_index = (index / 2)

	return if index <= 1
	return if @elements[parent_index] <= @elements[index]

	exchange(index, parent_index)
	bubble_up(parent_index)
    end

    def bubble_down(index)
	child_index = (index * 2)

	return if child_index > @elements.size - 1

	not_the_last_element = child_index < @elements.size - 1
	left_element = @elements[child_index]
	right_element = @elements[child_index + 1]
	child_index += 1 if not_the_last_element && right_element < left_element

	return if @elements[index] <= @elements[child_index]

	exchange(index, child_index)
	bubble_down(child_index)
    end

    def exchange(source, target)
	@elements[source], @elements[target] = @elements[target], @elements[source]
    end
end
pq = PriorityQueue.new


NUM_CORE = 16
NUM_LP = 32
#pq = Array.new(NUM_CORE, 0)
#(0 ... NUM_CORE).each { |x| pq<<0 }


core_time = Array.new(NUM_CORE, -1)
core_lp = Array.new(NUM_CORE, -1)
gvt = 0

event_q = Array.new(NUM_LP){Array.new}
rollback_q = Array.new(NUM_LP){Array.new}

send_match = /[\s\d]+: (\w+?): ([\s\d]+)->([\s\d]+) to core ([\s\d]+)( \(C\)|) GVT: ([\s\d]+)/
recv_match  =/[\s\d]+: (\w+?): ([\s\d]+)->([\s\d]+) from core ([\s\d]+)(\(C\)|)/
recv_stat_match = /stall: ([\s\d]+), mem_rq: ([\s\d]+), memld: ([\s\d]+), memst: ([\s\d]+), total: ([\s\d]+)/
null_match = /null from core ([\s\d]+)/
exec_match = /[\s\d]+: exec: ([\s\d]+)->([\s\d]+) at core ([\s\d]+)/

# Open and read file
File.foreach(filename) {|line|
  # Send events
   m = line.match(send_match)
   if m != nil
      target_lp = m[2].to_i
      time = m[3].to_i
      coreid = m[4].to_i
      cancellation = (m[5].match("C") != nil)
      gvt = m[6].to_i

      if pq.size > 0
        q = pq.pop
      else
        STDERR.puts "Deque from empty PQ: " + line
        exit(1)
      end

      if q != time
        STDERR.puts "Wrong event issued: " + line
        STDERR.puts "Timestamp - Expected: " + q.to_s + "\tActual: " + time.to_s
        exit(1)
      end

      if core_time[coreid] < 0
        core_time[coreid] = time
				core_lp[coreid] = target_lp
      else
        STDERR.puts "Sending event to occupied core" + line
        exit(1)
      end

      # GVT sanity check
      if gvt > (core_time.select{|x| x >= 0}).min
         STDERR.puts "Invalid GVT at line:" + line
         STDERR.puts core_time.join(' ')
         exit(1)
      end
   end

   m = line.match(exec_match)
   if m!= nil
     target_lp = m[1].to_i
     time = m[2].to_i
     # Causality check
     event_q[target_lp].select!{|x| x >= gvt}
     if (event_q[target_lp].size > 0 && event_q[target_lp].max > time)
       # keep track of events that will later be rolled back
			 rollback_q[target_lp] = rollback_q[target_lp] + event_q[target_lp].select{|x| x > time}
			 # event_q[target_lp].select{|x| x > time}.each{|x| puts "need to rollback " + target_lp.to_s + "-->" + time.to_s} 
       # puts event_q[target_lp].select{|x| x > time}
     end
     event_q[target_lp] << time
   end

   # Update received events in queue
   m = line.match(recv_match)
   if m != nil
      target_lp = m[2].to_i
      time = m[3].to_i
      coreid = m[4].to_i
			cancellation = m[5].match("C") != nil
			# if cancellation == true
			# 	# Received a rollback event, check if it was an expected one
			# 	puts "received rollback " + target_lp.to_s + "-->" + time.to_s
			# 	puts line
			# end
			
			if core_lp[coreid] == target_lp && rollback_q[core_lp[coreid]].size > 0
				if rollback_q[core_lp[coreid]].index(time) != nil
					rollback_q[core_lp[coreid]].delete_at(rollback_q[core_lp[coreid]].index(time))
					# puts "resend event " + target_lp.to_s + "-->" + time.to_s
				end
			end

      pq<<time

			m2 = line.match(recv_stat_match)
			# When it's the last recv statement from a core
			if m2 != nil
	      core_time[coreid] = -1
				core_lp[coreid] = -1
			end
   end

   # Update core table when null event found
  m = line.match(null_match)
  if m!= nil
    coreid = m[1].to_i
    core_time[coreid] = -1
		core_lp[coreid] = -1
  end
}
