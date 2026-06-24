require "test_helper"

class Design::GroupedByMatterTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "G #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "partitions into front/body/rear in reading order, unknowns to other" do
    %w[appendix chapter title_page copyright toc].each { |t| @ps.document_designs.create!(doc_type: t) }
    g = Design::DocumentDesign.grouped_by_matter(@ps.document_designs)
    assert_equal %w[title_page copyright toc], g[:frontmatter].map(&:doc_type)
    assert_equal %w[chapter], g[:bodymatter].map(&:doc_type)
    assert_equal %w[appendix], g[:rearmatter].map(&:doc_type)
    assert_equal [], g[:other].map(&:doc_type)
  end

  test "a doc_type in no matter group lands in other" do
    # front_page is a cover-panel type, in none of the three matter groups
    @ps.document_designs.create!(doc_type: "front_page")
    g = Design::DocumentDesign.grouped_by_matter(@ps.document_designs)
    assert_equal %w[front_page], g[:other].map(&:doc_type)
  end
end
