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

    def doc_type_row? = styleable_type == "Design::DocumentDesign"

    # Typed comparison for "equals the parent → inherit": BigDecimal vs "10.0",
    # stripped strings; nil and "" are equal (both mean inherit).
    def self.same_value?(field, a, b)
      type = type_for_attribute(field)
      ca = a.is_a?(String) ? a.strip.presence : a
      cb = b.is_a?(String) ? b.strip.presence : b
      type.cast(ca) == type.cast(cb)
    end

    private

    def normalize_doc_type_blanks
      STYLE_FIELDS.each { |f| self[f] = nil if self[f].is_a?(String) && self[f].strip.empty? }
    end

    # DB defaults (scale 100.0, text_color K100) are not overrides on doc-type rows.
    def clear_doc_type_defaults
      STYLE_FIELDS.each { |f| self[f] = nil unless attribute_came_from_user?(f) }
    end
  end
end
