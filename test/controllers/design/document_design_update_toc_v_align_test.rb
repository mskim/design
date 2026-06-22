require "test_helper"

class Design::DocumentDesignUpdateTocVAlignTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "TV #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "toc")
  end

  test "update persists toc_v_align" do
    patch design.theme_paper_size_document_design_path(@theme, @ps, @dd),
          params: { document_design: { toc_v_align: "center" } }
    assert_equal "center", @dd.reload.toc_v_align
  end
end
