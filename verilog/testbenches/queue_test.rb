# This script is used to generate a test pattern for the Priority Queue 
# Testbench (prio_q_tb.v). It generates a sequence of enqueue, dequeue and nop
# based on a provided pattern or randomly. The queue input data are generated
# randomly. Number of pattterns can be adjusted by editing 'iter_max' variable

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

prng = Random.new
pattern = ""

# Add manual test pattern here: 1 = ENQ, 2 = DEQ, 0= NOP
#pattern = "11111111111111111111111111111110000002222222222222222222222222222222"
#pattern = "111111111111111111111111111111111111100000000022222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222" 

count = 0;
iter = 0;
s=0;
pattern = pattern.split("")
iter_max = pattern.size > 0 ? pattern.size : 1000000
File.open("prio_q_test_data.dat","w"){ |f|
    while(iter < iter_max) do
	iter = iter + 1

	s = (pattern.size >0) ? pattern.shift.to_i : prng.rand(3)	
	case s
	when 1
	    if(count<63) then
		a = prng.rand(255)
		f.puts "1, 0, " + a.to_s
		pq<<a
		count = count + 1
	    end
	when 2
	    if(count >0) then
		f.puts "0, 1, " + pq.pop.to_s
		count = count - 1
	    end
	when 0
	    f.puts "0, 0, 0"
	end
    end
}
