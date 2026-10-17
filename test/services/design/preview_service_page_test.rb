require "test_helper"

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
    require "designcraft_rb"
    rows = DesignCraftRb::UnitRows.new.tap { svc.send(:populate_document, it) }
    assert_in_delta @dd.body_line_height, rows.rows["documents"].first["body_line_height"], 0.001
  end

  test "without its own body_line_count, text uses the paper size's line height" do
    dd = @ps.document_designs.create!(doc_type: "poem", body_line_count: nil)
    refute dd.reload.body_line_count_overridden?, "no body_line_count of its own"
    svc = Design::PreviewService.new(dd, paper_size: @ps)
    style = @theme.base_paragraph_styles.create!(name: "zz_lh2", font_size: 10)
    assert_in_delta @ps.body_line_height, svc.send(:build_style_attrs, style)[:line_height], 0.001
  end

  # 행간 (text_line_spacing) is the LEADING between lines, as book_write prints it
  # (PdfGenerationService#line_height_for, cd43ba5b): the pitch is font size +
  # leading. The raw 6.0 as the pitch overlapped the lines of every page that
  # uses the style's line height (copyright, inside cover, title page).
  test "a style's line height is its font size plus its leading" do
    svc = Design::PreviewService.new(@dd, paper_size: @ps)
    style = @theme.base_paragraph_styles.create!(name: "zz_lead", font_size: 9.5, text_line_spacing: 6.0)
    assert_in_delta 15.5, svc.send(:build_style_attrs, style)[:line_height], 0.001
    tight = @theme.base_paragraph_styles.create!(name: "zz_lead0", font_size: 12, text_line_spacing: 0.0)
    assert_in_delta 12.0, svc.send(:build_style_attrs, tight)[:line_height], 0.001
  end

  test "the TOC heading overlay is sized with the design's line height" do
    begin
      require "designcraft_rb"
      DesignCraftRb::Client.find_cli
    rescue LoadError, DesignCraftRb::CliNotFound => e
      skip e.message
    end
    toc = @ps.document_designs.create!(doc_type: "toc", body_line_count: 18, heading_height_in_lines: 4)
    result = Design::PreviewService.new(toc, paper_size: @ps, live: true).generate
    assert result[:success], result[:error]
    overlay = result[:pages].first[:overlay_data].find { it[:type] == "heading_area" }
    assert_in_delta 4 * toc.body_line_height, overlay[:height], 0.01
    refute_in_delta 4 * @ps.body_line_height, overlay[:height], 0.01
  end

  # The rendered line height changed (D3: the design's own body_line_count; then
  # 행간 read as leading, not as the pitch): caches stamped before are stale.
  test "the cache key carries the v5 version" do
    assert_equal "v5", Design::PreviewService::CACHE_VERSION
    assert Design::PreviewService.new(@dd, paper_size: @ps).send(:cache_fingerprint).start_with?("v5:")
  end

  test "a capped chapter body carries dropcap in its style attrs; a foreword, whose cap is chapter-only, does not" do
    cap = { "lines" => 3 }
    @dd.paragraph_styles.create!(name: "body", dropcap: cap)
    attrs = ->(dd) do
      style = dd.merged_paragraph_styles.find { it.name == "body" }
      Design::PreviewService.new(dd, paper_size: @ps).send(:build_style_attrs, style)
    end
    assert_equal 3, attrs.(@dd)[:dropcap]["lines"]

    foreword = @ps.document_designs.create!(doc_type: "foreword")
    assert_nil attrs.(foreword)[:dropcap]
  end
end
