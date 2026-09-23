module Design
  # D5: the conversion from the old five border fields (border_thickness,
  # border_color, border_side, rounded_corners, corner_radius) to the twelve
  # (a thickness and a colour per side, a corner preset per corner). Pure.
  #
  # The flag strings were written in two orders: the studio (and the engine)
  # read border_side as top,right,bottom,left; book_write's cover presets were
  # authored as left,top,right,bottom. rounded_corners is always tl,tr,br,bl.
  # Used by BorderUpgrade (the hosts' migration, the importers) and by
  # book_write's LegacyCoverBorders. DocProcessorRb::BoxDecoration.legacy_to_keys
  # applies the same rules to a .db that hasn't been re-exported.
  module LegacyBorder
    OLD_FIELDS = %w[border_thickness border_color border_side rounded_corners corner_radius].freeze
    SIDES = %w[top right bottom left].freeze
    CORNERS = %w[top_left top_right bottom_right bottom_left].freeze
    NEW_FIELDS = (SIDES.map { |s| "border_#{s}_thickness" } + SIDES.map { |s| "border_#{s}_color" } +
                  CORNERS.map { |c| "corner_#{c}" }).freeze
    SIDE_ORDERS = { studio: SIDES, cover: %w[left top right bottom] }.freeze
    PRESETS = %w[none small medium full].freeze

    module_function

    # Old-field hashes layered theme base → chapter → doc type: per field, a
    # nil or blank value falls back to the layer below. nil layers are skipped.
    def overlay(layers)
      OLD_FIELDS.index_with do |f|
        layers.compact.reverse.map { |layer| layer[f] }.find { |v| !(v.nil? || (v.is_a?(String) && v.strip.empty?)) }
      end
    end

    # A resolved old style → the twelve fields, every one set: a thickness per
    # side (0 = no line), the colour on every side while a line is drawn (nil
    # otherwise), a preset per corner ("none" = square). `large` → `full`.
    def convert(old, order: :studio)
      old = old.to_h.transform_keys(&:to_s)
      thickness = number(old["border_thickness"])
      drawn = thickness.positive?
      color = old["border_color"].to_s.strip.presence if drawn
      on_sides = on(old["border_side"], SIDE_ORDERS.fetch(order))
      preset = old["corner_radius"].to_s.strip
      preset = "full" if preset == "large"
      preset = "none" unless PRESETS.include?(preset)
      on_corners = on(old["rounded_corners"], CORNERS)

      out = {}
      SIDES.each do |side|
        out["border_#{side}_thickness"] = drawn && on_sides.include?(side) ? thickness : 0
        out["border_#{side}_color"] = color
      end
      CORNERS.each { |corner| out["corner_#{corner}"] = on_corners.include?(corner) ? preset : "none" }
      out
    end

    # The names whose flag is "1", reading `text` in `names`' order. Blank or
    # unreadable (not four 0/1 flags) = all of them.
    def on(text, names)
      flags = text.to_s.split(",").map(&:strip)
      return names.dup unless flags.size == 4 && flags.all? { |f| %w[0 1].include?(f) }
      names.zip(flags).filter_map { |name, flag| name if flag == "1" }
    end

    def number(value)
      n = Float(value.to_s.strip, exception: false)
      n && n.finite? && n.positive? ? n : 0
    end
  end
end
