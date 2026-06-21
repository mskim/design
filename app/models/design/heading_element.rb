module Design
  class HeadingElement < Design::ApplicationRecord
    self.table_name = "design_heading_elements"

    belongs_to :document_design, class_name: "Design::DocumentDesign"

    validates :element_type, :style_name, presence: true

    # UI hint only (C2 dropdown). NOT a validation: SizeGenerationService generates "quote".
    ELEMENT_TYPES = %w[title subtitle author publisher quote].freeze

    scope :in_order, -> { order(:position) }
  end
end
