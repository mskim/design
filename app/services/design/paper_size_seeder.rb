module Design
  # Seeds a paper size with one DocumentDesign per ALL_DOC_TYPES, mirroring
  # book_design's ThemeGeneratorService#create_paper_sizes_and_designs structurally
  # (heading-height + cover-panel attrs + default heading elements). It deliberately
  # does NOT create cover-panel paragraph styles — those need the host palette
  # (resolve_attrs/PALETTE), which the gem doesn't have; gem-created themes are
  # metadata-only. Idempotent: skips doc_types already present. Called from the
  # controller's `create` (NOT a model callback) so book_design's generator path
  # — which seeds its own designs after `paper_sizes.create!` — never collides.
  class PaperSizeSeeder
    def self.call(paper_size) = new(paper_size).call

    def initialize(paper_size) = @paper_size = paper_size

    def call
      existing = @paper_size.document_designs.pluck(:doc_type)
      (Design::DocumentDesign::ALL_DOC_TYPES - existing).each do |doc_type|
        attrs = { doc_type: doc_type }
        attrs[:heading_height_in_lines] = 0 unless Design::DocumentDesign.default_elements_for(doc_type).any?
        if Design::DocumentDesign::COVER_PANEL_TYPES.include?(doc_type)
          attrs[:layout_class] = "RLayout::CoverPage"
          attrs[:has_header] = false
          attrs[:has_footer] = false
        end
        dd = @paper_size.document_designs.create!(attrs)
        dd.populate_default_heading_elements
      end
      @paper_size
    end
  end
end
