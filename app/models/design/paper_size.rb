module Design
  class PaperSize < Design::ApplicationRecord
    self.table_name = "design_paper_sizes"

    belongs_to :theme, class_name: "Design::Theme"
    has_many :document_designs, class_name: "Design::DocumentDesign", dependent: :destroy
    has_many :paragraph_styles, as: :styleable, class_name: "Design::ParagraphStyle", dependent: :destroy

    validates :size_name, presence: true, uniqueness: { scope: :theme_id }
    validates :width_mm, :height_mm, numericality: { greater_than: 0 }
    validates :body_line_count, numericality: { greater_than: 0, only_integer: true }

    MM2PT = 2.8346456693

    def width_pt = width_mm * MM2PT
    def height_pt = height_mm * MM2PT
    def left_margin_pt = left_margin_mm * MM2PT
    def top_margin_pt = top_margin_mm * MM2PT
    def right_margin_pt = right_margin_mm * MM2PT
    def bottom_margin_pt = bottom_margin_mm * MM2PT
    def binding_margin_pt = binding_margin_mm * MM2PT

    def content_height_pt
      height_pt - top_margin_pt - bottom_margin_pt
    end

    def body_line_height
      content_height_pt / body_line_count
    end

    def display_name
      local_name.present? ? "#{local_name} (#{width_mm.to_i}x#{height_mm.to_i}mm)" : size_name
    end
  end
end
