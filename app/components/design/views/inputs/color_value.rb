module Design
  module Views
    module Inputs
      # Server-side twin of color_math.js: parse stored colour text ("CMYK=c,m,y,k",
      # "#rrggbb", legacy names) for the ColorField's initial swatch and summary.
      # summary must stay identical to color_math.js#summaryText.
      module ColorValue
        NAMED = { "black" => "#000000", "white" => "#ffffff", "red" => "#ff0000",
                  "blue" => "#0000ff", "green" => "#008000", "gray" => "#808080" }.freeze
        CHECKERBOARD = "background: repeating-conic-gradient(#e2e8f0 0% 25%, #ffffff 0% 50%) 50% / 8px 8px".freeze
        HEX = /\A#\h{6}\z/

        module_function

        def cmyk(str)
          s = str.to_s.strip
          return nil unless s.start_with?("CMYK=")
          parts = s.delete_prefix("CMYK=").split(",")
          return nil unless parts.size == 4
          parts.map { |p| Float(p, exception: false) }.then { |nums| nums.any?(&:nil?) ? nil : nums }
        end

        def format(str)
          s = str.to_s.strip
          return nil if s.empty?
          return :cmyk if cmyk(s)
          return :hex if s.match?(HEX)
          return :named if NAMED.key?(s.downcase)
          nil
        end

        def num(v) = (v.round(1) % 1).zero? ? v.round.to_s : v.round(1).to_s

        def summary(str)
          s = str.to_s.strip
          case format(s)
          when :cmyk then cmyk(s).zip(%w[C M Y K]).map { |v, l| "#{l}#{num(v)}" }.join(" ")
          when :hex then s.downcase
          when :named then s.downcase
          else s
          end
        end

        def swatch_hex(str)
          s = str.to_s.strip
          case format(s)
          when :cmyk
            c, m, y, k = cmyk(s).map { |v| v / 100.0 }
            "#%02x%02x%02x" % [ (1 - c) * (1 - k) * 255, (1 - m) * (1 - k) * 255, (1 - y) * (1 - k) * 255 ].map { |v| v.round.clamp(0, 255) }
          when :hex then s.downcase
          when :named then NAMED[s.downcase]
          end
        end

        def swatch_style(str)
          hex = swatch_hex(str)
          hex ? "background: #{hex}" : CHECKERBOARD
        end
      end
    end
  end
end
