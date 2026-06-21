module Design
  class ParagraphStyle < Design::ApplicationRecord
    self.table_name = "design_paragraph_styles"

    belongs_to :styleable, polymorphic: true

    VERTICAL_ALIGNS = %w[top middle bottom].freeze

    validates :name, presence: true, uniqueness: { scope: [:styleable_type, :styleable_id] }
    validates :vertical_align, inclusion: { in: VERTICAL_ALIGNS }, allow_nil: true
  end
end
