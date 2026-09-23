module Design
  # What the style panel's 테두리 section needs to know about a style's twelve
  # border/corner fields (D5), from this size's own row and its parent values:
  # each field's effective value, whether a 🔗 box shows linked, and what the
  # linked row shows. Pure: no rendering, no queries.
  class BorderLinkState
    MIXED = :mixed
    # A 🔗 box and the link groups it holds.
    BOXES = { "border" => %w[border_thickness border_color], "corners" => %w[corners] }.freeze

    # own: this size's ParagraphStyle row (or nil); parent: parent_values(name).
    def initialize(own:, parent:)
      @own = own
      @parent = parent
    end

    def fields(group) = Design::ParagraphStyle::LINK_GROUPS.fetch(group)
    def own(field) = @own&.[](field)
    def effective(field) = own(field).nil? ? @parent[field] : own(field)

    # Linked when every group in the box has one shared effective value.
    def linked?(box) = BOXES.fetch(box).none? { |group| common_effective(group) == MIXED }

    # The value all four fields store themselves, or nil.
    def common_own(group)
      values = fields(group).map { |f| own(f) }
      values.first if values.none?(&:nil?) && values.all? { |v| same?(group, v, values.first) }
    end

    # The four effective values' shared value (possibly nil), or MIXED.
    def common_effective(group)
      values = fields(group).map { |f| effective(f) }
      values.all? { |v| same?(group, v, values.first) } ? values.first : MIXED
    end

    # A linked row's dot: :changed if any of its fields is the user's, else
    # :generated if any is stored, else :inherited. states: field → state.
    def group_state(group, states)
      found = fields(group).map { |f| states.fetch(f) }
      if found.include?(:changed) then :changed
      elsif found.include?(:generated) then :generated
      else :inherited
      end
    end

    private

    def same?(group, a, b)
      return color_key(a) == color_key(b) if group == "border_color"
      Design::ParagraphStyle.same_value?(fields(group).first, a, b)
    end

    # A colour by meaning: a missing colour draws black (CMYK 0,0,0,100), CMYK
    # compares by its four numbers, hex ignores case. CMYK black and #000000
    # stay different (the engine draws them in different colour spaces).
    def color_key(value)
      text = value.to_s.strip
      if text.empty? then [ :cmyk, [ 0.0, 0.0, 0.0, 100.0 ] ]
      elsif (m = text.match(/\ACMYK\s*=\s*(.*)\z/i)) then [ :cmyk, m[1].split(",").map { |n| Float(n.strip, exception: false) || n.strip } ]
      elsif text.match?(/\A#\h{6}\z/) then [ :hex, text.downcase ]
      else [ :text, text ]
      end
    end
  end
end
