require "test_helper"
class Design::DocumentDesignUpsertTest < ActiveSupport::TestCase
  test "upsert_paragraph_style! creates then updates by name (no duplicate)" do
    theme = Design::Theme.create!(name: "U #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "blank_page")
    a = dd.upsert_paragraph_style!("xstyle", font_size: 10)
    b = dd.upsert_paragraph_style!("xstyle", font_size: 20)
    assert_equal a.id, b.id
    assert_equal 20.0, b.reload.font_size.to_f
    assert_equal 1, dd.paragraph_styles.where(name: "xstyle").count
  end
end
