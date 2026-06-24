require "test_helper"

class Design::DocumentDesignInteriorForTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "IF #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "returns interior designs in reading order, excluding cover panels" do
    epilogue   = @ps.document_designs.create!(doc_type: "epilogue")
    chapter    = @ps.document_designs.create!(doc_type: "chapter")
    title_page = @ps.document_designs.create!(doc_type: "title_page")
    _front     = @ps.document_designs.create!(doc_type: "front_page")

    result = Design::DocumentDesign.interior_for(@ps)

    assert_equal [ title_page, chapter, epilogue ], result
  end
end
