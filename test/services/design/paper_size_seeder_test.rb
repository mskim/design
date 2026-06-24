require "test_helper"

class Design::PaperSizeSeederTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "Seed #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "seeds one document design per ALL_DOC_TYPES" do
    Design::PaperSizeSeeder.call(@ps)
    assert_equal Design::DocumentDesign::ALL_DOC_TYPES.sort, @ps.document_designs.pluck(:doc_type).sort
  end

  test "is idempotent (skips existing doc types)" do
    Design::PaperSizeSeeder.call(@ps)
    assert_no_difference -> { @ps.document_designs.count } do
      Design::PaperSizeSeeder.call(@ps)
    end
  end

  test "sets cover-panel structural attrs and zero heading height for element-less types" do
    Design::PaperSizeSeeder.call(@ps)
    front = @ps.document_designs.find_by(doc_type: "front_page")
    assert_equal "RLayout::CoverPage", front.layout_class
    assert_not front.has_header
  end
end
