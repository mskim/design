module Design
  class DocumentDesign < Design::ApplicationRecord
    self.table_name = "design_document_designs"

    belongs_to :paper_size, class_name: "Design::PaperSize"
    has_one :theme, through: :paper_size
    has_many :paragraph_styles, as: :styleable, class_name: "Design::ParagraphStyle", dependent: :destroy
    has_many :heading_elements, -> { order(:position) }, class_name: "Design::HeadingElement", dependent: :destroy
    has_one_attached :heading_bg_image

    accepts_nested_attributes_for :heading_elements, allow_destroy: true

    validates :doc_type, presence: true, uniqueness: { scope: :paper_size_id }

    COVER_TYPES = %w[single_any_side single_left single_right spread back_to_back].freeze
    validates :cover_type, inclusion: { in: COVER_TYPES }, if: :has_document_cover?

    COPYRIGHT_DEFAULTS = { text_box_anchor_position: 7, text_box_grid_width: 4, text_box_grid_height: 6 }.freeze

    SINGLE_PAGE_TYPES = %w[title_page blank_page copyright inside_cover part_cover document_cover thanks dedication].freeze
    MULTI_PAGE_TYPES = %w[foreword prologue toc chapter poem appendix epilogue help information].freeze
    COVER_PANEL_TYPES = %w[front_page back_page seneca front_wing back_wing].freeze
    ALL_DOC_TYPES = (SINGLE_PAGE_TYPES + MULTI_PAGE_TYPES + COVER_PANEL_TYPES).freeze

    DEFAULT_HEADING_ELEMENTS = {
      "inside_cover" => %w[title subtitle author publisher],
      "part_cover" => %w[title subtitle],
      "document_cover" => %w[title subtitle],
      "blank_page" => [],
      "copyright" => [],
      # Cover panel types
      "front_page" => %w[title subtitle author publisher],
      "back_page" => [],
      "seneca" => %w[title author publisher],
      "front_wing" => [],
      "back_wing" => []
    }.freeze

    # All other doc_types default to ["title"]
    def self.default_elements_for(doc_type)
      DEFAULT_HEADING_ELEMENTS.fetch(doc_type, %w[title])
    end

    DEFAULT_HEADING_STYLES = {
      "title" => { font_size: 18, text_align: "center", space_before: 0, space_after: 6 },
      "subtitle" => { font_size: 14, text_align: "center", space_before: 0, space_after: 4 },
      "author" => { font_size: 11, text_align: "center", space_before: 0, space_after: 4 },
      "publisher" => { font_size: 10, text_align: "center", space_before: 0, space_after: 0 }
    }.freeze

    delegate :width_mm, :height_mm, :width_pt, :height_pt,
             :left_margin_mm, :top_margin_mm, :right_margin_mm, :bottom_margin_mm,
             :left_margin_pt, :top_margin_pt, :right_margin_pt, :bottom_margin_pt,
             :binding_margin_mm, :binding_margin_pt,
             to: :paper_size

    def effective_text_box_anchor_position
      text_box_anchor_position || (doc_type == "copyright" ? COPYRIGHT_DEFAULTS[:text_box_anchor_position] : nil)
    end

    def effective_text_box_grid_width
      text_box_grid_width || (doc_type == "copyright" ? COPYRIGHT_DEFAULTS[:text_box_grid_width] : nil)
    end

    def effective_text_box_grid_height
      text_box_grid_height || (doc_type == "copyright" ? COPYRIGHT_DEFAULTS[:text_box_grid_height] : nil)
    end

    def body_line_count
      self[:body_line_count] || paper_size.body_line_count
    end

    def body_line_count_overridden?
      self[:body_line_count].present?
    end

    def body_line_height
      content_height_pt / body_line_count
    end

    def content_width_pt(side: :single)
      base = width_pt - left_margin_pt - right_margin_pt
      base -= binding_margin_pt if side != :single
      base
    end

    def content_height_pt
      height_pt - top_margin_pt - bottom_margin_pt
    end

    def heading_height_pt
      (heading_height_in_lines || 0) * body_line_height
    end

    def column_width_pt(side: :single)
      (content_width_pt(side: side) - (column_count - 1) * gutter) / column_count
    end

    def single_page?
      SINGLE_PAGE_TYPES.include?(doc_type)
    end

    # Populate heading elements based on doc_type defaults.
    # Also ensures corresponding paragraph styles exist.
    def populate_default_heading_elements
      return if heading_elements.any?

      element_types = self.class.default_elements_for(doc_type)
      element_types.each_with_index do |etype, idx|
        heading_elements.create!(element_type: etype, style_name: etype, position: idx)
        ensure_heading_style_exists(etype)
      end
    end

    # Merge theme base styles with doc_type overrides.
    def merged_paragraph_styles
      base_styles = paper_size.theme.base_paragraph_styles.index_by(&:name)
      override_styles = paragraph_styles.index_by(&:name)

      all_names = (base_styles.keys + override_styles.keys).uniq
      all_names.map do |style_name|
        base = base_styles[style_name]
        override = override_styles[style_name]

        if override && base
          merge_style(base, override)
        elsif override
          override
        else
          base
        end
      end
    end

    # Creates (or returns existing) a document-level override for a base style.
    # Idempotent: if an override with the same name already exists, returns it.
    def override_for(base_name)
      existing = paragraph_styles.find_by(name: base_name)
      return existing if existing

      base = theme.base_paragraph_styles.find_by!(name: base_name)
      attrs = MERGEABLE_ATTRS.index_with { |attr| base[attr] }.compact
      paragraph_styles.create!(name: base_name, **attrs)
    end

    private

    def ensure_heading_style_exists(style_name)
      defaults = DEFAULT_HEADING_STYLES[style_name]
      return unless defaults

      # Check if style already exists in merged styles
      existing = merged_paragraph_styles.find { |s| s.name == style_name }
      return if existing

      # Create on this document_design with heading font from theme
      heading_font = theme&.base_heading_font
      paragraph_styles.create!(
        name: style_name,
        font: heading_font,
        **defaults
      )
    end

    MERGEABLE_ATTRS = %w[
      korean_name font font_size text_color text_align tracking space_width scale
      first_line_indent text_line_spacing space_before space_after
      space_before_in_lines space_after_in_lines left_indent right_indent
      bold_font emphasis_color
      fill_type fill_color fill_ending_color fill_gradient_direction
      border_thickness border_color border_side rounded_corners corner_radius
      padding_top padding_bottom bold_text_color emphasis_font
    ].freeze

    def merge_style(base, override)
      merged = override.dup
      MERGEABLE_ATTRS.each do |attr|
        merged[attr] = base[attr] if override[attr].nil?
      end
      merged
    end
  end
end
