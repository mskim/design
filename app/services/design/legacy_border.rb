module Design
  # D5: the conversion from the old five border fields (border_thickness,
  # border_color, border_side, rounded_corners, corner_radius) to the twelve
  # (a thickness and a colour per side, a corner preset per corner). Pure.
  # What the old chain set is pinned; what it left unset stays nil (latent),
  # so e.g. a row with only border_side still inherits its parent's thickness
  # on its flagged-on sides.
  #
  # The flag strings were written in two orders: the studio (and the engine)
  # read border_side as top,right,bottom,left; book_write's cover presets were
  # authored as left,top,right,bottom. rounded_corners is always tl,tr,br,bl.
  # Used by BorderUpgrade (the hosts' migration, the importers) and by
  # book_write's LegacyCoverBorders. DocProcessorRb::BoxDecoration.legacy_to_keys
  # reads the old keys at render time for a .db that hasn't been re-exported
  # (there nil and 0 draw the same, so it need not tell unset from off).
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

    # A resolved old style → the twelve fields (every key present). What the
    # old chain set is pinned; what it left unset stays nil, so it keeps
    # inheriting as the old model would have.
    #
    # Thickness: a number > 0 draws on the flagged sides (0 on the others) in
    # the colour on every side. Set but 0, negative or unreadable: no line on
    # any side (0) and no colour. Unset (nil / blank): a flagged-off side is 0,
    # a flagged-on side (or every side, with no flags) nil; a set colour stays
    # latent on every side.
    #
    # Corners: a real preset (small / medium / large → full) on the flagged
    # corners, "none" on the others. "none" or unreadable: all four "none".
    # Unset: a flagged-off corner "none", the others nil.
    def convert(old, order: :studio)
      old = old.to_h.transform_keys(&:to_s)
      out = {}
      side_values(old, SIDE_ORDERS.fetch(order)).each do |side, (thickness, color)|
        out["border_#{side}_thickness"] = thickness
        out["border_#{side}_color"] = color
      end
      corner_values(old).each { |corner, preset| out["corner_#{corner}"] = preset }
      out.slice(*NEW_FIELDS)
    end

    # side => [thickness, colour], in SIDES order.
    def side_values(old, names)
      color = old["border_color"].to_s.strip.presence
      flags = flags(old["border_side"], names)
      if unset?(old["border_thickness"])
        SIDES.index_with { |side| [ flags && !flags[side] ? 0 : nil, color ] }
      else
        thickness = number(old["border_thickness"])
        drawn = thickness.positive?
        SIDES.index_with { |side| drawn && (flags.nil? || flags[side]) ? [ thickness, color ] : [ 0, drawn ? color : nil ] }
      end
    end

    def corner_values(old)
      preset = old["corner_radius"].to_s.strip
      flags = flags(old["rounded_corners"], CORNERS)
      return CORNERS.index_with { |c| flags && !flags[c] ? "none" : nil } if preset.empty?
      preset = "full" if preset == "large"
      preset = "none" unless PRESETS.include?(preset)
      CORNERS.index_with { |c| preset != "none" && (flags.nil? || flags[c]) ? preset : "none" }
    end

    def unset?(value) = value.nil? || (value.is_a?(String) && value.strip.empty?)

    # { name => on? } from four 0/1 flags read in `names`' order; nil when the
    # text is blank or unreadable (= all on).
    def flags(text, names)
      list = text.to_s.split(",").map(&:strip)
      return nil unless list.size == 4 && list.all? { |f| %w[0 1].include?(f) }
      names.zip(list.map { |f| f == "1" }).to_h
    end

    def number(value)
      n = Float(value.to_s.strip, exception: false)
      n && n.finite? && n.positive? ? n : 0
    end
  end
end
