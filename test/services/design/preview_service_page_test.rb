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

  test "without its own body_line_count, text uses the paper size's line height" do
    dd = @ps.document_designs.create!(doc_type: "poem", body_line_count: nil)
    refute dd.reload.body_line_count_overridden?, "no body_line_count of its own"
    svc = Design::PreviewService.new(dd, paper_size: @ps)
    style = @theme.base_paragraph_styles.create!(name: "zz_lh2", font_size: 10)
    assert_in_delta @ps.body_line_height, svc.send(:build_style_attrs, style)[:line_height], 0.001
  end

  test "the TOC heading overlay is sized with the design's line height" do
    toc = @ps.document_designs.create!(doc_type: "toc", body_line_count: 18, heading_height_in_lines: 4)
    overlay = Design::PreviewService.new(toc, paper_size: @ps).send(:synthesize_toc_heading_overlay)
    assert_in_delta 4 * toc.body_line_height, overlay.first[:height], 0.001
    refute_in_delta 4 * @ps.body_line_height, overlay.first[:height], 0.001
  end

  # The design's own body_line_count changed the rendered line height (D3):
  # caches stamped before that are stale.
  test "the cache key carries the v4 version" do
    assert_equal "v4", Design::PreviewService::CACHE_VERSION
    assert Design::PreviewService.new(@dd, paper_size: @ps).send(:cache_fingerprint).start_with?("v4:")
  end
end
