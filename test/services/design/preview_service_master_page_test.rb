require "test_helper"

class Design::PreviewServiceMasterPageTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "PV #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225, body_line_count: 23)
    @dd = @ps.document_designs.create!(doc_type: "toc", toc_v_align: "center", body_line_count: 18)
  end

  test "master_page gets dd-level body_line_count and toc_v_align" do
    require "designcraft_rb"
    svc = Design::PreviewService.new(@dd, paper_size: @ps)
    rows = DesignCraftRb::UnitRows.new
    svc.send(:populate_document, rows)
    svc.send(:populate_master_page, rows)
    mp = rows.rows["master_page"].first
    assert_equal 18, mp["body_line_count"]
    assert_equal "center", mp["toc_v_align"]
    assert_in_delta @dd.body_line_height, mp["body_line_height"], 0.001
  end
end
