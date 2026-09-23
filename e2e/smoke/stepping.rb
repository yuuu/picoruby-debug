def square(n)
  r = n * n
  r
end

total = 0
i = 0
binding.debugger
while i < 3
  total += square(i)
  i += 1
end
puts "total=#{total}"
