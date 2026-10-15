require "test_helper"

# The studio's previews are laid out by DesignCraft, as the host prints books: the result hash
# and overlay rows the studio reads, or the preview's error when DesignCraft can't.
class Design::PreviewServiceDesignCraftTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "DC #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
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

  # The page-heading / text-box table the populate methods ask (doc_processor_rb's DocumentType).
  test "title pages and covers centre a page heading; all but those and a blank page have a text box" do
    layout = ->(type) { Design::PreviewService.new(@ps.document_designs.find_or_create_by!(doc_type: type), paper_size: @ps).send(:resolved_doc_type) }
    heading, text_box = Design::DocumentDesign::ALL_DOC_TYPES.partition { layout.(it).uses_page_heading? }

    assert_equal %w[ dedication document_cover front_page inside_cover part_cover thanks title_page ], heading.sort
    assert_equal %w[ blank_page ], text_box.reject { layout.(it).needs_text_box? }
    assert_equal "chapter", layout.("foreword").name
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

  test "previews take no lock, so they render side by side" do
    designcraft_cli!
    threads = %w[chapter title_page front_page].map { |type| Thread.new { preview(type) } }

    threads.map { it.join(120) ? it.value : flunk("a preview never finished") }.each { assert it[:success], it[:error] }
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

  test "when DesignCraft can't, the preview is its error" do
    service = Design::PreviewService.new(@ps.document_designs.create!(doc_type: "chapter"), paper_size: @ps, live: true)
    service.define_singleton_method(:render_with_designcraft) { |*| raise "no font" }

    result = service.generate

    refute result[:success]
    assert_equal "no font", result[:error]
    assert_empty result[:pages]
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
  # it painted under their content (their stream transforms first).
  test "a document cover's page colour lies under DesignCraft's page" do
    designcraft_cli!
    dd = @ps.document_designs.create!(doc_type: "document_cover", page_bg_color: "CMYK=0,10,30,0")
    result = Design::PreviewService.new(dd, paper_size: @ps, live: true).generate

    assert result[:success], result[:error]
    corner = Vips::Image.new_from_file(result[:jpg_path].to_s).getpoint(5, 5)
    assert_operator corner[2], :<, 230, "the corner is the page colour, not white: #{corner.inspect}" # its blue channel
    assert result[:pages].first[:overlay_data].any? { it[:type] == "heading_title" }
  end

  test "a change to DesignCraft's layout is a new cache key" do
    require "designcraft_rb"
    chapter = Design::PreviewService.new(@ps.document_designs.create!(doc_type: "chapter"), paper_size: @ps)
    was = DesignCraftRb.layout_digest
    before = chapter.send(:cache_fingerprint)
    DesignCraftRb.instance_variable_set(:@layout_digest, "0123456789abcdef")

    assert_not_equal before, chapter.send(:cache_fingerprint)
  ensure
    DesignCraftRb.instance_variable_set(:@layout_digest, was)
  end
end
