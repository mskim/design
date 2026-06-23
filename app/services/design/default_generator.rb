module Design
  class DefaultGenerator
    def self.call(paper_size) = new(paper_size).call

    def initialize(paper_size) = @paper_size = paper_size

    def call
      fill_layout
      @paper_size.document_designs.each { |dd| generate_headings_for(dd) }   # no-op until Task 4
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

    # Implemented in Task 4.
    def generate_headings_for(document_design) = nil
  end
end
