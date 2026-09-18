require "test_helper"

class Design::PreviewServicePrintModeTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "PM #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  teardown do
    [ true, false ].each { |pm| Design::PreviewService.new(@dd, paper_size: @ps, print_mode: pm).clear_cache rescue nil }
  end

  def para_min_x(page) = page[:overlay_data].select { |o| o[:type] == "paragraph" }.map { |o| o[:x].to_f }.min

  test "binding applies to the chapter-type layouts only" do
    assert_equal %w[chapter foreword prologue epilogue appendix help information].sort, Design::DocumentDesign::BINDING_DOC_TYPES.sort
    assert @dd.binding_applies?
    refute @ps.document_designs.new(doc_type: "poem").binding_applies?
    refute @ps.document_designs.new(doc_type: "front_page").binding_applies?, "falls back to the Chapter layout, still never bound"
  end

  test "print mode is a separate cache: its own subfolder and fingerprint" do
    normal = Design::PreviewService.new(@dd, paper_size: @ps)
    print = Design::PreviewService.new(@dd, paper_size: @ps, print_mode: true)
    assert print.print_mode?
    refute normal.print_mode?
    assert_equal normal.send(:preview_dir).join("print"), print.send(:preview_dir)
    refute_equal normal.send(:cache_fingerprint), print.send(:cache_fingerprint)
  end

  test "a doc type the engine never binds ignores print mode (one cache)" do
    dd = @ps.document_designs.create!(doc_type: "title_page")
    svc = Design::PreviewService.new(dd, paper_size: @ps, print_mode: true)
    refute svc.print_mode?
    assert_equal Design::PreviewService.new(dd, paper_size: @ps).send(:preview_dir), svc.send(:preview_dir)
  end

  test "print mode reaches the layout: a chapter's text starts after the binding on page 1, not on page 2" do
    @ps.update_columns(binding_margin_mm: 10)
    result = Design::PreviewService.new(@dd, paper_size: @ps, print_mode: true).generate
    assert result[:success], result[:error]
    assert_equal true, result[:print_mode]
    assert_in_delta (@ps.left_margin_pt + @ps.binding_margin_pt).to_f, para_min_x(result[:pages][0]), 0.5, "odd page: spine on the left"
    assert_in_delta @ps.left_margin_pt.to_f, para_min_x(result[:pages][1]), 0.5, "even page: binding on the right"

    normal = Design::PreviewService.new(@dd, paper_size: @ps).generate
    assert_equal false, normal[:print_mode]
    assert_in_delta @ps.left_margin_pt.to_f, para_min_x(normal[:pages][0]), 0.5
  end
end
