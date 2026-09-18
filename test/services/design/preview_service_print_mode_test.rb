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

  test "binding applies to every interior layout the engine binds" do
    expected = %w[chapter foreword prologue epilogue appendix help information poem toc copyright
                  title_page thanks dedication inside_cover part_cover]
    assert_equal expected.sort, Design::DocumentDesign::BINDING_DOC_TYPES.sort
    assert @dd.binding_applies?
    assert @ps.document_designs.new(doc_type: "poem").binding_applies?
    assert @ps.document_designs.new(doc_type: "title_page").binding_applies?
    refute @ps.document_designs.new(doc_type: "front_page").binding_applies?, "falls back to the Chapter layout, still never bound"
    refute @ps.document_designs.new(doc_type: "document_cover").binding_applies?, "full bleed: only its heading would shift"
    refute @ps.document_designs.new(doc_type: "blank_page").binding_applies?, "draws nothing"
  end

  test "every doc type is either bound or a known exclusion" do
    unbound = Design::DocumentDesign::ALL_DOC_TYPES - Design::DocumentDesign::BINDING_DOC_TYPES
    assert_equal (Design::DocumentDesign::COVER_PANEL_TYPES + %w[document_cover blank_page]).sort, unbound.sort
  end

  test "print mode is a separate cache: its own subfolder and fingerprint" do
    normal = Design::PreviewService.new(@dd, paper_size: @ps)
    print = Design::PreviewService.new(@dd, paper_size: @ps, print_mode: true)
    assert print.print_mode?
    refute normal.print_mode?
    assert_equal normal.send(:preview_dir).join("print"), print.send(:preview_dir)
    refute_equal normal.send(:cache_fingerprint), print.send(:cache_fingerprint)
  end

  # doc_processor_rb cf4eb37 changed what a chapter renders in print mode
  # (heading, running heads and tables now shift too), not the normal
  # render: only print caches go stale, so only the print key moves.
  test "the print key carries its own version; the normal key doesn't" do
    assert_equal "print-v2", Design::PreviewService::PRINT_CACHE_VERSION
    normal = Design::PreviewService.new(@dd, paper_size: @ps)
    print = Design::PreviewService.new(@dd, paper_size: @ps, print_mode: true)
    parts = ->(svc) { svc.send(:cache_fingerprint_parts) }
    assert_equal parts.(normal) + [ "print-v2" ], parts.(print)
    refute_includes parts.(normal).join, "print"
  end

  test "a doc type without a print preview ignores print mode (one cache)" do
    dd = @ps.document_designs.create!(doc_type: "blank_page")
    svc = Design::PreviewService.new(dd, paper_size: @ps, print_mode: true)
    refute svc.print_mode?
    assert_equal Design::PreviewService.new(dd, paper_size: @ps).send(:preview_dir), svc.send(:preview_dir)
  end

  test "a normal clear_cache also removes the print/ folder" do
    print = Design::PreviewService.new(@dd, paper_size: @ps, print_mode: true)
    result = print.generate
    assert result[:success], result[:error]
    assert File.exist?(print.page_jpg_path(1))
    Design::PreviewService.new(@dd, paper_size: @ps).clear_cache
    refute File.exist?(print.page_jpg_path(1))
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

  # Poem and the title page render with their own layouts (Poem, TitlePage),
  # not Chapter: print mode must reach those too.
  { "poem" => "paragraph", "title_page" => nil }.each do |doc_type, overlay_type|
    test "print mode shifts a #{doc_type}'s page 1 right by the binding" do
      @ps.update_columns(binding_margin_mm: 10)
      dd = @ps.document_designs.create!(doc_type: doc_type)
      min_x = ->(result) do
        overlays = result[:pages][0][:overlay_data]
        overlays = overlays.select { |o| o[:type] == overlay_type } if overlay_type
        overlays.map { |o| o[:x].to_f }.min
      end
      normal = Design::PreviewService.new(dd, paper_size: @ps).generate
      print = Design::PreviewService.new(dd, paper_size: @ps, print_mode: true).generate
      assert normal[:success], normal[:error]
      assert print[:success], print[:error]
      assert_equal true, print[:print_mode]
      refute_nil min_x.(normal), "#{doc_type} page 1 has overlays"
      assert_in_delta min_x.(normal) + @ps.binding_margin_pt.to_f, min_x.(print), 0.5, "odd page: spine on the left"
    ensure
      [ true, false ].each { |pm| Design::PreviewService.new(dd, paper_size: @ps, print_mode: pm).clear_cache rescue nil } if dd
    end
  end
end
