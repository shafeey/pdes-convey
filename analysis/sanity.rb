filename = "../verilog/sim.txt"

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
gvt = 0

event_q = Array.new(NUM_LP){Array.new}

send_match = /[\s\d]+: (\w+?): ([\s\d]+)->([\s\d]+) to core ([\s\d]+)( \(C\)|) GVT: ([\s\d]+)/
recv_match  =/[\s\d]+: (\w+?): ([\s\d]+)->([\s\d]+) from core ([\s\d]+)/
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
       puts line
       #puts event_q[target_lp].select{|x| x > time}
     end
     event_q[target_lp] << time
   end


   m = line.match(recv_match)
   if m != nil
      target_lp = m[2].to_i
      time = m[3].to_i
      coreid = m[4].to_i

      pq<<time
      core_time[coreid] = -1
   end

  m = line.match(null_match)
  if m!= nil
    coreid = m[1].to_i
    core_time[coreid] = -1
  end
}
