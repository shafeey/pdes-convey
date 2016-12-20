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
cancellation_q = Array.new(NUM_LP){Array.new}
rollback_q = Array.new(NUM_CORE){Array.new}

send_match = /[\s\d]+: (\w+?): ([\s\d]+)->([\s\d]+) to core ([\s\d]+)( \(C\)|) GVT: ([\s\d]+)/
recv_match  =/[\s\d]+: (\w+?): ([\s\d]+)->([\s\d]+) from core ([\s\d]+)(\(C\)|)/
recv_stat_match = /stall: ([\s\d]+), mem_rq: ([\s\d]+), memld: ([\s\d]+), memst: ([\s\d]+), total: ([\s\d]+)/
null_match = /null from core ([\s\d]+)/
exec_match = /[\s\d]+: exec: ([\s\d]+)->([\s\d]+) at core ([\s\d]+)(\(C\)|)/

cycle = 0
# Open and read file
File.foreach(filename) {|line|
  m = line.match(/#\s+(\d+):/)
 cycle = m[1].to_i if m != nil

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
     coreid = m[3].to_i
     cancellation = (m[4].match("C") != nil)

     # Causality check
     event_q[target_lp].select!{|x| x >= gvt}
     if cancellation
        # check for cancelled event in the event queue
        pos = event_q[target_lp].find_index(time)
        if pos != nil
           # event found at queue, has been processed already
           # remove it from the processed queue, to prevent generating rollback later
           event_q[target_lp].delete_at(pos)
        else
           # keep a record, to prevent insertion into processed event queue
           cancellation_q[target_lp].push(time)
        end
     else
        if (event_q[target_lp].size > 0 && event_q[target_lp].max > time)
          # keep track of events that will later be rolled back
           # and remove them from processed list
           # puts  event_q[target_lp].select{|x| x > time}
             rollback_q[coreid] = event_q[target_lp].select{|x| x > time}
             # event_q[target_lp].select{|x| x > time}.each{|x| puts "need to rollback " \
             #                                        + target_lp.to_s + "-->" + x.to_s \
             #                                        + " at core: " + coreid.to_s + " cycle: " + cycle.to_s} 
             event_q[target_lp].delete_if{|x| x > time}
               # puts           rollback_q[coreid]
          # puts event_q[target_lp].select{|x| x > time}
        end
        if cancellation_q[target_lp].size > 0 && cancellation_q[target_lp].find_index(time) != nil
           # event has a cancellation message waiting, don't insert into processed queue
           # remove cancellation message from cancellation queue
           cancellation_q[target_lp].delete_at(cancellation_q[target_lp].find_index(time))
        else
           event_q[target_lp] << time # insert processed event to queue
        end
     end
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
			
      # If the event matches any item in rollback_q, it's an event that needs to be processed again
      if core_lp[coreid] == target_lp && rollback_q[coreid].size > 0
         if rollback_q[coreid].index(time) != nil
            rollback_q[coreid].delete_at(rollback_q[coreid].index(time))
            # puts "resend event " + target_lp.to_s + "-->" + time.to_s + " at core: " + coreid.to_s \
            #    + " cycle: " + cycle.to_s
         end
      end

      pq<<time

      m2 = line.match(recv_stat_match)
      if m2 != nil # When it's the last recv statement from a core
         if rollback_q[coreid].size > 0 # Some rollback events weren't sent
            puts core_lp[coreid].to_s + ":"
            puts rollback_q[coreid]
            STDERR.puts "Rollback events remain unsent: " + line
         end
         core_time[coreid] = -1
            core_lp[coreid] = -1
      end
   end

   # Update core table when null event found
  m = line.match(null_match)
  if m!= nil
    if line.match(recv_stat_match) != nil
      coreid = m[1].to_i
      core_time[coreid] = -1
		  core_lp[coreid] = -1
    end
  end
}
