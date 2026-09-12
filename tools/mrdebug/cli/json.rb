module MRDebug
  module CLI
    # mainline mruby ships no JSON gem (docs/plan-phase4.md step 2), so this
    # is a small, DAP-scoped encoder/decoder rather than a general library
    # (no surrogate-pair \u support, no streaming). Core String methods
    # only (see CLAUDE.md's "Avoid mruby-string-ext methods").
    module Json
      class ParseError < StandardError; end

      def self.generate(obj)
        case obj
        when nil then 'null'
        when true then 'true'
        when false then 'false'
        when String then generate_string(obj)
        when Symbol then generate_string(obj.to_s)
        when Integer then obj.to_s
        when Float then obj.to_s
        when Array
          '[' + obj.map { |v| generate(v) }.join(',') + ']'
        when Hash
          pairs = obj.map { |k, v| "#{generate_string(k.to_s)}:#{generate(v)}" }
          '{' + pairs.join(',') + '}'
        else
          raise ArgumentError, "MRDebug::CLI::Json cannot encode a #{obj.class}"
        end
      end

      HEX_DIGITS = '0123456789abcdef'.freeze

      def self.generate_string(s)
        out = '"'
        i = 0
        while i < s.size
          byte = s.getbyte(i)
          case byte
          when 0x22 then out += '\\"' # "
          when 0x5c then out += '\\\\' # backslash
          when 0x0a then out += '\\n'
          when 0x0d then out += '\\r'
          when 0x09 then out += '\\t'
          else
            if byte < 0x20
              out += "\\u00#{HEX_DIGITS[(byte >> 4) & 0xf, 1]}#{HEX_DIGITS[byte & 0xf, 1]}"
            else
              out += s[i, 1]
            end
          end
          i += 1
        end
        out + '"'
      end

      def self.parse(str)
        parser = Parser.new(str)
        value = parser.parse_value
        parser.skip_ws
        value
      end

      # A minimal recursive-descent parser over a plain String, tracking a
      # byte offset by hand (no StringScanner in mruby core).
      class Parser
        def initialize(str)
          @s = str
          @i = 0
          @n = str.size
        end

        def parse_value
          skip_ws
          c = peek
          raise ParseError, 'unexpected end of input' if c.nil?
          case c
          when '{' then parse_object
          when '[' then parse_array
          when '"' then parse_string
          when 't' then parse_literal('true', true)
          when 'f' then parse_literal('false', false)
          when 'n' then parse_literal('null', nil)
          else parse_number
          end
        end

        def skip_ws
          @i += 1 while @i < @n && space?(peek)
        end

        private

        def peek
          @i < @n ? @s[@i, 1] : nil
        end

        def advance
          c = peek
          @i += 1
          c
        end

        def expect(char)
          raise ParseError, "expected #{char.inspect} at byte #{@i}" unless peek == char
          advance
        end

        def space?(c)
          c == ' ' || c == "\t" || c == "\n" || c == "\r"
        end

        def digit?(c)
          !c.nil? && c >= '0' && c <= '9'
        end

        def parse_object
          expect('{')
          obj = {}
          skip_ws
          if peek == '}'
            advance
            return obj
          end
          loop do
            skip_ws
            key = parse_string
            skip_ws
            expect(':')
            obj[key] = parse_value
            skip_ws
            sep = advance
            return obj if sep == '}'
            raise ParseError, "expected ',' or '}' at byte #{@i}" unless sep == ','
          end
        end

        def parse_array
          expect('[')
          arr = []
          skip_ws
          if peek == ']'
            advance
            return arr
          end
          loop do
            arr << parse_value
            skip_ws
            sep = advance
            return arr if sep == ']'
            raise ParseError, "expected ',' or ']' at byte #{@i}" unless sep == ','
          end
        end

        def parse_string
          expect('"')
          out = ''
          loop do
            c = advance
            raise ParseError, 'unterminated string' if c.nil?
            return out if c == '"'
            if c == '\\'
              out += parse_escape
            else
              out += c
            end
          end
        end

        def parse_escape
          esc = advance
          case esc
          when '"' then '"'
          when '\\' then '\\'
          when '/' then '/'
          when 'n' then "\n"
          when 't' then "\t"
          when 'r' then "\r"
          when 'b' then "\b"
          when 'f' then "\f"
          when 'u' then parse_unicode_escape
          else raise ParseError, "bad escape \\#{esc}"
          end
        end

        # ASCII only (no mainline Integer#chr to build this from otherwise).
        ASCII_BYTES =
          ("\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f" \
           "\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f" \
           " !\"\#$%&'()*+,-./0123456789:;<=>?" \
           "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_" \
           "`abcdefghijklmnopqrstuvwxyz{|}~\x7f").freeze

        def parse_unicode_escape
          hex = @s[@i, 4]
          raise ParseError, 'truncated \\u escape' if hex.nil? || hex.size < 4
          @i += 4
          codepoint = hex.to_i(16)
          raise ParseError, "\\u#{hex}: non-ASCII \\u escapes are not supported" if codepoint > 0x7f
          ASCII_BYTES[codepoint, 1]
        end

        def parse_literal(word, value)
          i = 0
          while i < word.size
            raise ParseError, "expected #{word.inspect} at byte #{@i}" unless peek == word[i, 1]
            advance
            i += 1
          end
          value
        end

        def parse_number
          start = @i
          @i += 1 if peek == '-'
          raise ParseError, "invalid number at byte #{start}" unless digit?(peek)
          @i += 1 while digit?(peek)
          is_float = false
          if peek == '.'
            is_float = true
            @i += 1
            @i += 1 while digit?(peek)
          end
          if peek == 'e' || peek == 'E'
            is_float = true
            @i += 1
            @i += 1 if peek == '+' || peek == '-'
            @i += 1 while digit?(peek)
          end
          text = @s[start, @i - start]
          is_float ? parse_float(text) : text.to_i
        end

        # No mainline String#to_f, so build the Float by hand.
        def parse_float(text)
          neg = text[0, 1] == '-'
          s = neg ? text[1, text.size - 1] : text
          e_pos = s.index('e') || s.index('E')
          mantissa = e_pos ? s[0, e_pos] : s
          exponent = e_pos ? s[(e_pos + 1), s.size - e_pos - 1].to_i : 0

          dot_pos = mantissa.index('.')
          int_part = dot_pos ? mantissa[0, dot_pos] : mantissa
          frac_part = dot_pos ? mantissa[(dot_pos + 1), mantissa.size - dot_pos - 1] : ''

          value = int_part.to_i.to_f
          scale = 0.1
          i = 0
          while i < frac_part.size
            value += frac_part[i, 1].to_i * scale
            scale *= 0.1
            i += 1
          end
          value *= (10.0**exponent) if exponent != 0
          neg ? -value : value
        end
      end
    end
  end
end
