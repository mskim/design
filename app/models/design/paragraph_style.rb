module Design
  class ParagraphStyle < Design::ApplicationRecord
    self.table_name = "design_paragraph_styles"

    belongs_to :styleable, polymorphic: true

    include Design::Overridable
    # Unlike PaperSize, NO before_create capture: paragraph-style overrides are
    # created by the generator, so an explicit font_size at creation is not marked
    # overridden — user font_size overrides are recorded via mark_overridden_from_changes
    # on the edit path instead.
    GENERATABLE_FIELDS = %w[font_size].freeze

    VERTICAL_ALIGNS = %w[top middle bottom].freeze

    validates :name, presence: true, uniqueness: { scope: [:styleable_type, :styleable_id] }
    validates :vertical_align, inclusion: { in: VERTICAL_ALIGNS }, allow_nil: true

    # Fields a doc-type style can inherit/override. korean_name is a label (not an
    # override); vertical_align is table-cell only and theme-level (no doc-type consumer).
    STYLE_FIELDS = (Design::DocumentDesign::MERGEABLE_ATTRS - %w[korean_name]).freeze

    # D5: a thickness and a colour per side, a corner preset per corner — each
    # an ordinary style field that inherits on its own. Spelled out again in
    # DocumentDesign::MERGEABLE_ATTRS (a shared constant would be an autoload
    # cycle); Design::BorderFieldsTest pins the two equal.
    SIDES = %w[top right bottom left].freeze
    CORNERS = %w[top_left top_right bottom_right bottom_left].freeze
    BORDER_THICKNESS_FIELDS = %w[border_top_thickness border_right_thickness border_bottom_thickness
                                 border_left_thickness].freeze
    BORDER_COLOR_FIELDS = %w[border_top_color border_right_color border_bottom_color border_left_color].freeze
    CORNER_FIELDS = %w[corner_top_left corner_top_right corner_bottom_right corner_bottom_left].freeze
    BORDER_FIELDS = (BORDER_THICKNESS_FIELDS + BORDER_COLOR_FIELDS + CORNER_FIELDS).freeze
    # As symbols: the keys of the style attributes the layout engines read for a box's borders
    # and corners (doc_processor_rb's BoxDecoration::KEYS, designcraft_rb's adapter).
    BORDER_KEYS = BORDER_FIELDS.map(&:to_sym).freeze
    # Relative to the box's shorter side s (DocProcessorRb::BoxDecoration.radius):
    # small 6% (≥ 2 pt), medium 15% (≥ 4 pt), full s/2.
    CORNER_SIZES = %w[none small medium full].freeze
    # The style panel's 🔗 groups: one request writes, or reverts, all four.
    LINK_GROUPS = { "border_thickness" => BORDER_THICKNESS_FIELDS, "border_color" => BORDER_COLOR_FIELDS,
                    "corners" => CORNER_FIELDS }.freeze

    # The group whose four fields are exactly `fields` (any order), or nil.
    def self.link_group_for(fields)
      names = Array(fields).map(&:to_s).sort
      LINK_GROUPS.find { |_, group| group.sort == names }&.first
    end

    # pt-valued, paper-size-dependent fields: an edit on one size changes the
    # other sizes proportionally (see DocumentDesign#set_style_field!).
    SCALED_FIELDS = %w[
      font_size text_line_spacing space_before space_after first_line_indent
      left_indent right_indent padding_top padding_bottom
    ].freeze

    before_validation :normalize_doc_type_blanks, if: :doc_type_row?
    after_initialize :clear_doc_type_defaults, if: -> { new_record? && doc_type_row? }

    # Sizes and spacing (pt, lines, %) can't be negative; indents and tracking can.
    NON_NEGATIVE_FIELDS = (%w[
      font_size scale space_width text_line_spacing space_before space_after
      space_before_in_lines space_after_in_lines padding_top padding_bottom
    ] + BORDER_THICKNESS_FIELDS).freeze
    # A zero size or scale draws nothing.
    POSITIVE_FIELDS = %w[font_size scale].freeze
    NUMBER_LIMIT = 10_000

    # A plain decimal: optional sign, digits with an optional fraction (or a
    # bare fraction). No exponent ("1e999" is Infinity); Float() would also
    # take "0x1A", "1_0".
    DECIMAL = /\A[+-]?(\d+(\.\d*)?|\.\d+)\z/

    # The style panel's select options (StylePanelContent renders these).
    TEXT_ALIGNS = %w[left center right justify].freeze
    FILL_TYPES = %w[none solid gradient].freeze
    GRADIENT_DIRECTIONS = %w[top_to_bottom bottom_to_top left_to_right right_to_left angle].freeze
    OPTION_FIELDS = {
      "text_align" => TEXT_ALIGNS, "fill_type" => FILL_TYPES, "fill_gradient_direction" => GRADIENT_DIRECTIONS
    }.merge(CORNER_FIELDS.index_with { CORNER_SIZES }).freeze

    FONT_FIELDS = %w[font bold_font emphasis_font].freeze
    COLOR_FIELDS = (%w[text_color bold_text_color emphasis_color fill_color fill_ending_color] + BORDER_COLOR_FIELDS).freeze
    # What Inputs::ColorValue reads: "CMYK=c,m,y,k" (plain decimals, spaces
    # around each allowed), "#rrggbb", or a legacy colour name.
    COLOR = /\A(CMYK=(\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*)(,\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*){3}|#\h{6}|(?i:black|white|red|blue|green|gray))\z/

    # A body style's drop cap (spec 2026-10-17): one JSON field. nil inherits, {"enabled"=>false}
    # is explicitly off, else {lines, chars, font, color, align_left_edge, scale_descenders};
    # blank font/color = the body's own.
    DROPCAP_KEYS = %w[lines chars font color align_left_edge scale_descenders].freeze
    DROPCAP_LINES = (2..6)
    DROPCAP_CHARS = (1..4)
    DROPCAP_DEFAULT = { "lines" => 2, "chars" => 1, "align_left_edge" => true, "scale_descenders" => false }.freeze
    DROPCAP_OFF = { "enabled" => false }.freeze

    # The canonical dropcap Hash (string keys, integer counts, boolean flags, blank font/colour
    # and unknown keys dropped) from a Hash, ActionController::Parameters or JSON string;
    # nil for blank. A count that is not a whole number stays as given so validation reports it.
    def self.normalize_dropcap(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      value = (JSON.parse(value) rescue nil) if value.is_a?(String)
      return nil unless value.is_a?(Hash)

      value = value.transform_keys(&:to_s)
      return DROPCAP_OFF.dup if [ false, "false", "0" ].include?(value["enabled"])

      out = {}
      %w[lines chars].each do |k|
        next if value[k].blank?
        out[k] = value[k].is_a?(Integer) ? value[k] : Integer(value[k].to_s.strip, 10, exception: false) || value[k]
      end
      %w[font color].each { |k| out[k] = value[k].to_s.strip if value[k].to_s.strip.present? }
      %w[align_left_edge scale_descenders].each do |k|
        out[k] = ActiveModel::Type::Boolean.new.cast(value[k]) unless value[k].nil? || value[k] == ""
      end
      out.presence
    end

    # Only the style panel's field save asks for these (row.valid?(:style_panel));
    # importers, the size generator and set_style_field!'s own saves don't.
    validate :numeric_style_fields, on: :style_panel, if: :doc_type_row?
    validate :text_style_fields, on: :style_panel, if: :doc_type_row?
    validate :dropcap_field, on: :style_panel, if: :doc_type_row?

    before_validation { self.dropcap = self.class.normalize_dropcap(dropcap) if dropcap_changed? }

    def doc_type_row? = styleable_type == "Design::DocumentDesign"

    # Proportional values are rounded to 2 decimals, so a scaled value can land
    # up to half a hundredth away from a parent stored with more precision.
    SCALED_TOLERANCE = BigDecimal("0.005")

    # Typed comparison for "equals the parent → inherit": BigDecimal vs "10.0",
    # stripped strings; nil and "" are equal (both mean inherit). With a
    # tolerance, numeric values within it (inclusive) are equal.
    def self.same_value?(field, a, b, tolerance: 0)
      # The JSON type's cast alone would tell "2" from 2 and a JSON string from a Hash.
      return normalize_dropcap(a) == normalize_dropcap(b) if field.to_s == "dropcap"

      type = type_for_attribute(field)
      ca = type.cast(a.is_a?(String) ? a.strip.presence : a)
      cb = type.cast(b.is_a?(String) ? b.strip.presence : b)
      return (ca - cb).abs <= tolerance if tolerance.positive? && ca.is_a?(Numeric) && cb.is_a?(Numeric)
      ca == cb
    end

    # "Equals the parent → inherit" check: SCALED_FIELDS tolerate the rounding of
    # proportional values (SCALED_TOLERANCE); every other field compares exactly.
    def self.inherits_value?(field, value, parent_value)
      tolerance = SCALED_FIELDS.include?(field.to_s) ? SCALED_TOLERANCE : 0
      same_value?(field, value, parent_value, tolerance: tolerance)
    end

    private

    # Decimal columns cast "abc" to 0 and "12pt" to 12 silently, so check what
    # was typed. Only fields assigned in this edit are checked (came_from_user?,
    # via Design::Overridable) — a legacy row never blocks an unrelated save.
    def numeric_style_fields
      STYLE_FIELDS.each do |f|
        next unless type_for_attribute(f).type == :decimal && attribute_came_from_user?(f)
        raw = read_attribute_before_type_cast(f)
        next if raw.nil? || (raw.is_a?(String) && raw.strip.empty?)
        text = raw.to_s.strip
        number = raw.is_a?(Numeric) ? raw : (text.match?(DECIMAL) ? text.to_d : nil)
        if number.nil? || !number.finite?
          errors.add(f, I18n.t("design.style_panel.errors.not_a_number"))
        elsif number.abs > NUMBER_LIMIT
          errors.add(f, I18n.t("design.style_panel.errors.too_large", max: NUMBER_LIMIT))
        elsif POSITIVE_FIELDS.include?(f) && !number.positive?
          errors.add(f, I18n.t("design.style_panel.errors.positive"))
        elsif NON_NEGATIVE_FIELDS.include?(f) && number.negative?
          errors.add(f, I18n.t("design.style_panel.errors.negative"))
        end
      end
    end

    # Selects, fonts and colours take only what the panel's
    # controls produce. A font may also be the value already stored on this
    # row or its parent, so a legacy font round-trips. Like the numbers, only
    # fields assigned in this edit are checked.
    def text_style_fields
      STYLE_FIELDS.each do |f|
        next if f == "dropcap" # dropcap_field checks its parts
        next unless attribute_came_from_user?(f)
        value = self[f]
        next if value.nil? || (value.is_a?(String) && value.strip.empty?)
        text = value.to_s
        error = if OPTION_FIELDS.key?(f) then :invalid_option unless OPTION_FIELDS[f].include?(text)
                elsif FONT_FIELDS.include?(f) then :invalid_option unless allowed_fonts(f).include?(text)
                elsif COLOR_FIELDS.include?(f) then :invalid_color unless text.match?(COLOR)
                end
        errors.add(f, I18n.t("design.style_panel.errors.#{error}")) if error
      end
    end

    def allowed_fonts(f)
      stored = attribute_in_database(f)
      parent = styleable.respond_to?(:parent_values) ? styleable.parent_values(name)[f] : nil
      Design::Theme::AVAILABLE_FONTS + [ stored, parent ].compact
    end

    # The drop cap's parts, as the panel offers them: lines 2–6, chars 1–4, a colour as
    # COLOR, a font as the font fields (its stored or parent cap's font round-trips).
    def dropcap_field
      return unless attribute_came_from_user?("dropcap")
      cap = self.class.normalize_dropcap(dropcap)
      return if cap.nil? || cap == DROPCAP_OFF

      error = ->(key) { errors.add(:dropcap, I18n.t("design.style_panel.errors.dropcap_#{key}")) }
      error.(:lines) unless DROPCAP_LINES.include?(cap.fetch("lines", DROPCAP_DEFAULT["lines"]))
      error.(:chars) unless DROPCAP_CHARS.include?(cap.fetch("chars", DROPCAP_DEFAULT["chars"]))
      error.(:color) if cap["color"] && !cap["color"].match?(COLOR)
      error.(:font) if cap["font"] && !allowed_dropcap_fonts.include?(cap["font"])
    end

    def allowed_dropcap_fonts
      stored = self.class.normalize_dropcap(attribute_in_database("dropcap"))
      parent = styleable.respond_to?(:parent_values) ? styleable.parent_values(name)["dropcap"] : nil
      Design::Theme::AVAILABLE_FONTS + [ stored, self.class.normalize_dropcap(parent) ].filter_map { |c| c&.dig("font") }
    end

    def normalize_doc_type_blanks
      STYLE_FIELDS.each { |f| self[f] = nil if self[f].is_a?(String) && self[f].strip.empty? }
    end

    # DB defaults (scale 100.0, text_color K100) are not overrides on doc-type rows.
    def clear_doc_type_defaults
      STYLE_FIELDS.each { |f| self[f] = nil unless attribute_came_from_user?(f) }
    end
  end
end
