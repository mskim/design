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
  end
end
