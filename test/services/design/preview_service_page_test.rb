require "test_helper"
require "tmpdir"

class Design::PreviewServicePageTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "PSP #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225, body_line_count: 23)
    @dd = @ps.document_designs.create!(doc_type: "chapter", body_line_count: 18)
  end

  test "text uses the design's body line height (its own body_line_count), like the grid" do
    refute_in_delta @ps.body_line_height, @dd.body_line_height, 0.001
    svc = Design::PreviewService.new(@dd, paper_size: @ps)
    style = @theme.base_paragraph_styles.create!(name: "zz_lh", font_size: 10)
    assert_in_delta @dd.body_line_height, svc.send(:build_style_attrs, style)[:line_height], 0.001
    Dir.mktmpdir do |dir|
      db = svc.send(:create_db_document, File.join(dir, "t.db"))
      svc.send(:populate_document, db)
      assert_in_delta @dd.body_line_height, db.document_info.body_line_height, 0.001
      db.close
    end
  end
end
