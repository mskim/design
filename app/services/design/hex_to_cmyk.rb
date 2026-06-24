module Design
  class HexToCmyk
    def self.call(hex)
      return nil if hex.nil? || hex == ""
      h = hex.delete_prefix("#")
      r = h[0, 2].to_i(16) / 255.0
      g = h[2, 2].to_i(16) / 255.0
      b = h[4, 2].to_i(16) / 255.0
      k = 1 - [ r, g, b ].max
      if k >= 1.0
        [ 0, 0, 0, 100 ]
      else
        c = ((1 - r - k) / (1 - k) * 100).round
        m = ((1 - g - k) / (1 - k) * 100).round
        y = ((1 - b - k) / (1 - k) * 100).round
        [ c, m, y, (k * 100).round ]
      end
    end
  end
end
