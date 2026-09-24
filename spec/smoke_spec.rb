# Keep these to output that's identical on mruby and PicoRuby: stepping into
# core mrblib (Integer#times) or a watch firing inside Kernel#puts prints
# VM-specific paths.
RSpec.describe 'mrdebug (mrdbg) session' do
  it 'stops at binding.debugger and handles print/next/breakpoints/bt/list' do
    transcript = debug(<<~RUBY, 'p x', 'n', 'p y', 'break 9', 'break Foo#bar', 'break', 'c', 'p c', 'bt', 'c', 'p n', 'list', 'c')
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
      puts "z=\#{z}"
    RUBY

    expect(transcript).to eq [
      [nil, "Stop: script.rb:13\n"],
      ['p x', "10\n"],
      ['n', "Stop: script.rb:14\n"],
      ['p y', "nil\n"],
      ['break 9', "Breakpoint 1 added at script.rb:9\n"],
      ['break Foo#bar', "Breakpoint 2 added at Foo#bar\n"],
      ['break', "  #1 script.rb:9\n  #2 Foo#bar\n"],
      ['c', "Breakpoint 1: script.rb:9\n"],
      ['p c', "15\n"],
      ['bt', "#0 script.rb:9\n#1 script.rb:14\n"],
      ['c', "Breakpoint 2: Foo#bar\n"],
      ['p n', "15\n"],
      ['list', <<~LIST],
           1  class Foo
        => 2    def bar(n)
           3      n * 2
           4    end
           5  end
           6  
           7  def add(a, b)
      LIST
      ['c', "z=30\n"],
    ]
  end

  it 'steps into calls, nexts over lines, and honors conditional breakpoints' do
    transcript = debug(<<~RUBY, 's', 's', 's', 'p n', 'n', 'n', 'p r', 'break 3 if n == 2', 'c', 'p r', 'd', 'c')
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
      puts "total=\#{total}"
    RUBY

    expect(transcript).to eq [
      [nil, "Stop: script.rb:8\n"],
      ['s', "Stop: script.rb:9\n"],
      ['s', "Stop: script.rb:10\n"],
      ['s', "Stop: script.rb:1\n"],
      ['p n', "0\n"],
      ['n', "Stop: script.rb:2\n"],
      ['n', "Stop: script.rb:3\n"],
      ['p r', "0\n"],
      ['break 3 if n == 2', "Breakpoint 1 added at script.rb:3 if n == 2\n"],
      ['c', "Breakpoint 1: script.rb:3\n"],
      ['p r', "4\n"],
      ['d', "Deleted all breakpoints\n"],
      ['c', "total=5\n"],
    ]
  end

  it 'moves between frames with up/down/frame and evaluates in the selected one' do
    transcript = debug(<<~RUBY, 'break 3', 'c', 'up', 'p x', 'list', 'up', 'down 5', 'p a', 'frame 1', 'frame 9', 'c')
      def inner(a)
        b = a + 1
        b
      end

      def outer(x)
        inner(x * 2)
      end

      binding.debugger
      puts outer(10)
    RUBY

    expect(transcript).to eq [
      [nil, "Stop: script.rb:10\n"],
      ['break 3', "Breakpoint 1 added at script.rb:3\n"],
      ['c', "Breakpoint 1: script.rb:3\n"],
      ['up', "#1 script.rb:7\n"],
      ['p x', "10\n"],
      ['list', <<~LIST],
           2    b = a + 1
           3    b
           4  end
           5  
           6  def outer(x)
        => 7    inner(x * 2)
           8  end
           9  
           10  binding.debugger
           11  puts outer(10)
      LIST
      ['up', "#2 script.rb:11\n"],
      ['down 5', "#0 script.rb:3\n"],
      ['p a', "20\n"],
      ['frame 1', "#1 script.rb:7\n"],
      ['frame 9', "No frame #9\n"],
      ['c', "21\n"],
    ]
  end
end
