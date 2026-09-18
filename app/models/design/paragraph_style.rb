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
      font_size scale text_line_spacing space_before space_after
      space_before_in_lines space_after_in_lines border_thickness padding_top padding_bottom
    ].freeze

    # A plain decimal: optional sign, digits with an optional fraction (or a
    # bare fraction), optional exponent. Float() would also take "0x1A", "1_0".
    DECIMAL = /\A[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\z/

    # Only the style panel's field save asks for this (row.valid?(:style_panel));
    # importers, the size generator and set_style_field!'s own saves don't.
    validate :numeric_style_fields, on: :style_panel, if: :doc_type_row?

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
        if number.nil?
          errors.add(f, I18n.t("design.style_panel.errors.not_a_number"))
        elsif NON_NEGATIVE_FIELDS.include?(f) && number.negative?
          errors.add(f, I18n.t("design.style_panel.errors.negative"))
        end
      end
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
