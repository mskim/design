module Design
  class TableStyle < Design::ApplicationRecord
    self.table_name = "design_table_styles"

    belongs_to :theme, class_name: "Design::Theme"

    ALLOWED_NAMES = %w[grid zebra striped minimal simple].freeze
    BORDER_STYLES = %w[full horizontal none outer_only].freeze
    FONT_WEIGHTS  = %w[normal bold].freeze

    validates :name, presence: true, inclusion: { in: ALLOWED_NAMES },
              uniqueness: { scope: :theme_id }
    validates :border_style, inclusion: { in: BORDER_STYLES }, allow_nil: true
    validates :header_font_weight, inclusion: { in: FONT_WEIGHTS }, allow_nil: true
  end
end
