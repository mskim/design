require "test_helper"

class Design::LocalizationTest < ActiveSupport::TestCase
  def panel(doc_type: "toc")
    theme = Design::Theme.create!(name: "L #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: doc_type)
    c = Design::Views::DocumentDesigns::PropertiesPanel.new(theme: theme, paper_size: ps, document_design: dd, editable: true)
    # REQUIRED: the panel calls helpers.*_path during render (no request context
    # in a unit test). Stub its URL methods, EXACTLY as the existing
    # test/components/design/properties_panel_test.rb#render_panel does:
    c.define_singleton_method(:form_action_url) { "/x" }
    c.define_singleton_method(:preview_url) { "/x/preview" }
    c.define_singleton_method(:csrf_token) { "test-token" }
    c.define_singleton_method(:typography_panel_url) { |o| "/x/panel/#{o.id}" }
    c.define_singleton_method(:typography_override_url) { |_n| "/x/override" }
    c.define_singleton_method(:typography_new_style_url) { "/x/new" }
    c.call
  end

  test "v-align select keeps English values but shows Korean labels in :ko" do
    html = I18n.with_locale(:ko) { panel }
    # stored values stay English (the renderer reads these):
    assert_includes html, %(value="center")
    assert_includes html, %(value="top")
    assert_includes html, %(value="bottom")
    # visible labels are Korean:
    assert_includes html, "가운데"
    assert_includes html, "아래"
  end

  test "properties panel renders Korean labels, no English leftovers" do
    html = I18n.with_locale(:ko) { panel }
    assert_includes html, "레이아웃"          # Layout tab
    assert_includes html, "본문 줄 수"         # Body Line Count
    assert_includes html, "단락정의"           # Typography (user glossary)
    refute_includes html, ">Layout<"
    refute_includes html, "Body Line Count"
    assert_not_includes html, "translation missing"
  end

  test "fields render Korean, no English leftovers" do
    theme = Design::Theme.create!(name: "F #{SecureRandom.hex(3)}", locale: "ko")
    style = theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    html = I18n.with_locale(:ko) { Design::Views::ParagraphStyles::Fields.new(paragraph_style: style, editable: true).call }
    assert_includes html, "자간"       # Tracking
    assert_includes html, "어간"       # Space Width (user glossary)
    assert_includes html, "행간"       # Line Spacing
    refute_includes html, "Tracking"
    refute_includes html, "Identity"
    assert_not_includes html, "translation missing"
  end
end
