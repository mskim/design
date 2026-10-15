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

  test "a cover panel stays with doc_processor_rb, and turning DesignCraft on is a new cache key" do
    front = Design::PreviewService.new(@ps.document_designs.create!(doc_type: "front_page"), paper_size: @ps)
    chapter = Design::PreviewService.new(@ps.document_designs.create!(doc_type: "chapter"), paper_size: @ps)

    assert_not front.send(:designcraft?)
    assert chapter.send(:designcraft?)
    on = chapter.send(:cache_fingerprint)
    Design.config.designcraft = -> { false }
    assert_not_equal on, chapter.send(:cache_fingerprint)
  end
end
