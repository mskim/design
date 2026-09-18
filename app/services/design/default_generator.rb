module Design
  class DefaultGenerator
    def self.call(paper_size) = new(paper_size).call

    def self.call_for(document_design)
      new(document_design.paper_size).generate_headings_for(document_design)
    end

    def initialize(paper_size) = @paper_size = paper_size

    def call
      fill_layout
      @paper_size.document_designs.each { |dd| generate_headings_for(dd) }   # non-chapter is a no-op
      @paper_size
    end

    def fill_layout
      m = GenerationRules.margins_for(@paper_size.width_mm, @paper_size.height_mm)
      assigns = {
        left_margin_mm:    m[:left],  top_margin_mm:    m[:top],
        right_margin_mm:   m[:right], bottom_margin_mm: m[:bottom],
        binding_margin_mm: m[:binding],
        body_line_count:   GenerationRules.body_line_count_for(@paper_size.height_mm)
      }
      assigns.reject! { |attr, _| @paper_size.overridden?(attr) }
      @paper_size.update_columns(assigns) if assigns.any?
    end

    # Scaled heading sizes live on chapter only, as sparse font_size rows; every
    # other doc type on the size resolves them through chapter (theme → chapter
    # → doc type). A user-overridden font_size is left alone.
    def generate_headings_for(document_design)
      return unless document_design.doc_type == "chapter"
      theme  = @paper_size.theme
      height = @paper_size.height_mm
      GenerationRules::HEADING_SCALED_STYLES.each do |name|
        base = theme.base_paragraph_styles.find_by(name: name)
        next unless base&.font_size
        row = document_design.paragraph_styles.find_or_initialize_by(name: name)
        next if row.overridden?(:font_size)
        row.font_size = GenerationRules.scaled_size(base.font_size, height)
        row.save!
      end
    end
  end
end
