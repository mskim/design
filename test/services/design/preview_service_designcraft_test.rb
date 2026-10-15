require "test_helper"

# With Design.config.designcraft the studio's previews are laid out by DesignCraft, as the host
# prints books: the same result hash and overlay rows, and doc_processor_rb when DesignCraft
# can't (or for a doc type it doesn't lay out).
class Design::PreviewServiceDesignCraftTest < ActiveSupport::TestCase
  setup do
    @was = Design.config.designcraft
    Design.config.designcraft = true
    @theme = Design::Theme.create!(name: "DC #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  teardown do
    Design.config.designcraft = @was
  end

  def designcraft_cli!
    require "designcraft_rb"
    DesignCraftRb::Client.find_cli
  rescue LoadError, DesignCraftRb::CliNotFound => e
    skip e.message
  end

  def preview(doc_type, **options)
    dd = @ps.document_designs.create!(doc_type: doc_type)
    Design::PreviewService.new(dd, paper_size: @ps, live: true, **options).generate
  end

  test "a chapter is laid out by DesignCraft, its overlays where DesignCraft set the lines" do
    designcraft_cli!
    result = preview("chapter")

    assert result[:success], result[:error]
    rows = result[:pages].first[:overlay_data]
    assert_equal %w[ heading_area heading_title ], rows.first(2).map { it[:type] }
    assert rows.any? { it[:type] == "paragraph" && it[:markup].present? && it[:width].positive? }
    assert File.exist?(result[:jpg_path])
  end

  test "the TOC's entries and its heading come from DesignCraft, not synthesized" do
    designcraft_cli!
    rows = preview("toc")[:pages].first[:overlay_data]

    assert_equal 1, rows.count { it[:type] == "heading_area" }
    assert rows.any? { it[:type] == "toc_entry" }
  end

  test "the binding margin only in print mode" do
    designcraft_cli!
    x = ->(result) { result[:pages].first[:overlay_data].find { it[:type] == "paragraph" }[:x] }

    assert_operator x.(preview("chapter", print_mode: true)), :>, x.(preview("foreword"))
  end

  test "when DesignCraft can't, doc_processor_rb lays the design out" do
    service = Design::PreviewService.new(@ps.document_designs.create!(doc_type: "chapter"), paper_size: @ps, live: true)
    service.define_singleton_method(:render_with_designcraft) { |*| nil }

    result = service.generate

    assert result[:success], result[:error]
    assert_operator result[:pages].first[:overlay_data].size, :>, 0
  end

  test "the cover panels are laid out as the printed cover: the front's heading measured from the top" do
    designcraft_cli!
    result = preview("front_page")

    assert result[:success], result[:error]
    title = result[:pages].first[:overlay_data].find { it[:type] == "heading_title" }
    assert title, "the title's region"
    assert_operator title[:y], :>, @ps.height_pt / 4 # centred down the page, as the printed front cover
    assert_operator title[:y] + title[:height], :<, @ps.height_pt
  end

  test "the spine is a spine's width, the back page's text its copy" do
    designcraft_cli!
    spine = preview("seneca")
    back = preview("back_page")

    assert_in_delta Design::PreviewService::COVER_SPINE_MM * Design::PaperSize::MM2PT, spine[:page_width], 0.01
    assert spine[:pages].first[:overlay_data].any? { it[:type] == "heading_title" }
    assert_equal [ %w[ paragraph body ] ], back[:pages].first[:overlay_data].map { it.values_at(:type, :markup) }
  end

  # The document cover's colour bleeds over the page, behind its title page; DesignCraft's PDFs need
  # it painted under their content (their stream transforms first) and their CMaps untyped first.
  test "a document cover's page colour lies under DesignCraft's page" do
    designcraft_cli!
    dd = @ps.document_designs.create!(doc_type: "document_cover", page_bg_color: "CMYK=0,10,30,0")
    result = Design::PreviewService.new(dd, paper_size: @ps, live: true).generate

    assert result[:success], result[:error]
    corner = Vips::Image.new_from_file(result[:jpg_path].to_s).getpoint(5, 5)
    assert_operator corner[2], :<, 230, "the corner is the page colour, not white: #{corner.inspect}" # its blue channel
    assert result[:pages].first[:overlay_data].any? { it[:type] == "heading_title" }
  end

  test "every doc type is DesignCraft's, and turning DesignCraft on is a new cache key" do
    assert_empty Design::DocumentDesign::ALL_DOC_TYPES - Design::PreviewService::DESIGNCRAFT_DOC_TYPES
    chapter = Design::PreviewService.new(@ps.document_designs.create!(doc_type: "chapter"), paper_size: @ps)
    on = chapter.send(:cache_fingerprint)
    Design.config.designcraft = -> { false }
    assert_not_equal on, chapter.send(:cache_fingerprint)
  end
end
