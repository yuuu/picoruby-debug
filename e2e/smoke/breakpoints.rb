class Foo
  def bar(n)
    n * 2
  end
end

def add(a, b)
  c = a + b
  c
end

x = 10
binding.debugger
y = add(x, 5)
z = Foo.new.bar(y)
puts "z=#{z}"
