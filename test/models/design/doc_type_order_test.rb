require "test_helper"

class Design::DocTypeOrderTest < ActiveSupport::TestCase
  test "by_reading_order sorts doc_types into canonical book order, unknowns last" do
    theme = Design::Theme.create!(name: "DT #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    # create in a deliberately scrambled order
    %w[appendix title_page blank_page chapter copyright].each { |t| ps.document_designs.create!(doc_type: t) }
    ordered = Design::DocumentDesign.by_reading_order(ps.document_designs).map(&:doc_type)
    assert_equal %w[title_page copyright chapter appendix blank_page], ordered
    # title_page < copyright < chapter < appendix (canonical), blank_page (unknown) last
  end
end
