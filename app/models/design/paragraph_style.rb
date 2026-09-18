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

    # pt-valued, paper-size-dependent fields: an edit on one size changes the
    # other sizes proportionally (see DocumentDesign#set_style_field!).
    SCALED_FIELDS = %w[
      font_size text_line_spacing space_before space_after first_line_indent
      left_indent right_indent padding_top padding_bottom
    ].freeze

    before_validation :normalize_doc_type_blanks, if: :doc_type_row?
    after_initialize :clear_doc_type_defaults, if: -> { new_record? && doc_type_row? }

    # Sizes and spacing (pt, lines, %) can't be negative; indents and tracking can.
    NON_NEGATIVE_FIELDS = %w[
      font_size scale space_width text_line_spacing space_before space_after
      space_before_in_lines space_after_in_lines border_thickness padding_top padding_bottom
    ].freeze
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
    CORNER_RADII = %w[none small medium large].freeze
    OPTION_FIELDS = {
      "text_align" => TEXT_ALIGNS, "fill_type" => FILL_TYPES,
      "fill_gradient_direction" => GRADIENT_DIRECTIONS, "corner_radius" => CORNER_RADII
    }.freeze

    FONT_FIELDS = %w[font bold_font emphasis_font].freeze
    # "top,right,bottom,left" / "tl,tr,br,bl" on-off flags.
    FLAG_FIELDS = %w[border_side rounded_corners].freeze
    FLAGS = /\A[01](,[01]){3}\z/
    COLOR_FIELDS = %w[text_color bold_text_color emphasis_color fill_color fill_ending_color border_color].freeze
    # What Inputs::ColorValue reads: "CMYK=c,m,y,k" (plain decimals, spaces
    # around each allowed), "#rrggbb", or a legacy colour name.
    COLOR = /\A(CMYK=(\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*)(,\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*){3}|#\h{6}|(?i:black|white|red|blue|green|gray))\z/

    # Only the style panel's field save asks for these (row.valid?(:style_panel));
    # importers, the size generator and set_style_field!'s own saves don't.
    validate :numeric_style_fields, on: :style_panel, if: :doc_type_row?
    validate :text_style_fields, on: :style_panel, if: :doc_type_row?

    def doc_type_row? = styleable_type == "Design::DocumentDesign"

    # Proportional values are rounded to 2 decimals, so a scaled value can land
    # up to half a hundredth away from a parent stored with more precision.
    SCALED_TOLERANCE = BigDecimal("0.005")

    # Typed comparison for "equals the parent → inherit": BigDecimal vs "10.0",
    # stripped strings; nil and "" are equal (both mean inherit). With a
    # tolerance, numeric values within it (inclusive) are equal.
    def self.same_value?(field, a, b, tolerance: 0)
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

    # Selects, fonts, flag strings and colours take only what the panel's
    # controls produce. A font may also be the value already stored on this
    # row or its parent, so a legacy font round-trips. Like the numbers, only
    # fields assigned in this edit are checked.
    def text_style_fields
      STYLE_FIELDS.each do |f|
        next unless attribute_came_from_user?(f)
        value = self[f]
        next if value.nil? || (value.is_a?(String) && value.strip.empty?)
        text = value.to_s
        error = if OPTION_FIELDS.key?(f) then :invalid_option unless OPTION_FIELDS[f].include?(text)
                elsif FONT_FIELDS.include?(f) then :invalid_option unless allowed_fonts(f).include?(text)
                elsif FLAG_FIELDS.include?(f) then :invalid_flags unless text.match?(FLAGS)
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

    def normalize_doc_type_blanks
      STYLE_FIELDS.each { |f| self[f] = nil if self[f].is_a?(String) && self[f].strip.empty? }
    end

    # DB defaults (scale 100.0, text_color K100) are not overrides on doc-type rows.
    def clear_doc_type_defaults
      STYLE_FIELDS.each { |f| self[f] = nil unless attribute_came_from_user?(f) }
    end
  end
end
