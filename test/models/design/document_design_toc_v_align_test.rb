require "test_helper"

class Design::DocumentDesignTocVAlignTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "TV #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "toc")
  end

  test "effective_toc_v_align defaults to bottom when unset" do
    assert_nil @dd.toc_v_align
    assert_equal "bottom", @dd.effective_toc_v_align
  end

  test "effective_toc_v_align returns the stored value when set" do
    @dd.update!(toc_v_align: "center")
    assert_equal "center", @dd.effective_toc_v_align
  end
end
