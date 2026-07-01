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

  test "cover-panel doc_types land in cover, in physical spread order (COVER_PANEL_ORDER), not other" do
    # insert out of physical order; expect back_wing → seneca → front_page (spread order)
    %w[back_wing front_page seneca].each { |t| @ps.document_designs.create!(doc_type: t) }
    g = Design::DocumentDesign.grouped_by_matter(@ps.document_designs)
    assert_equal %w[back_wing seneca front_page], g[:cover].map(&:doc_type)
    assert_not_includes g[:other].map(&:doc_type), "front_page"
    assert_equal [], g[:other].map(&:doc_type)
  end

  test "COVER_PANEL_ORDER is the left-to-right spread order" do
    assert_equal %w[back_wing back_page seneca front_page front_wing], Design::DocumentDesign::COVER_PANEL_ORDER
  end
end
