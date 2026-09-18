require "test_helper"

class Design::LocalizationTest < ActiveSupport::TestCase
  def panel_render(doc_type: "toc")
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
    c.define_singleton_method(:typography_style_url) { |n| "/x/styles/#{n}" }
    c.define_singleton_method(:typography_new_style_url) { "/x/new" }
    c.call
  end

  test "v-align select keeps English values but shows Korean labels in :ko" do
    html = I18n.with_locale(:ko) { panel_render }
    # stored values stay English (the renderer reads these):
    assert_includes html, %(value="center")
    assert_includes html, %(value="top")
    assert_includes html, %(value="bottom")
    # visible labels are Korean:
    assert_includes html, "가운데"
    assert_includes html, "아래"
  end

  test "properties panel renders Korean labels, no English leftovers" do
    html = I18n.with_locale(:ko) { panel_render }
    assert_includes html, "레이아웃"          # Layout tab
    assert_includes html, "본문 줄 수"         # Body Line Count
    assert_includes html, "단락정의"           # Typography (user glossary)
    refute_includes html, ">Layout<"
    refute_includes html, "Body Line Count"
    assert_not_includes html, "translation missing"
  end

  test "fields render Korean, no English leftovers" do
    html = I18n.with_locale(:ko) { fields_render }
    assert_includes html, "자간"       # Tracking
    assert_includes html, "어간"       # Space Width (user glossary)
    assert_includes html, "행간"       # Line Spacing
    refute_includes html, "Tracking"
    refute_includes html, "Identity"
    assert_not_includes html, "translation missing"
  end

  test "preview overlay labels are Korean" do
    html = I18n.with_locale(:ko) { preview_render }
    assert_includes html, "제목"   # Title overlay label
  end

  test "preview error is Korean" do
    html = I18n.with_locale(:ko) { preview_error_render }
    assert_includes html, "미리보기 생성 실패"
    refute_includes html, "Preview generation failed"
  end

  test "paragraph panel renders Korean chrome" do
    html = I18n.with_locale(:ko) { paragraph_panel_render }
    %w[design.panel.back design.style_panel.sections.type_text design.style_panel.sections.border
       design.style_panel.all_sizes design.style_panel.push_to_theme design.style_panel.all_options
       design.style_panel.status.saving design.fields.size].each do |key|
      assert_includes html, CGI.escapeHTML(I18n.t(key, locale: :ko)), key
    end
    assert_includes html, I18n.t("design.style_panel.revert_all", count: 1, locale: :ko)
    refute_includes html, ">Save<"
    refute_includes html, "Revert to base"
    refute_includes html, ">Back<"
    assert_not_includes html, "translation missing"
  end

  # --- helpers for the cross-component no-leftover guard ---

  def fields_render
    theme = Design::Theme.create!(name: "GF #{SecureRandom.hex(3)}", locale: "ko")
    style = theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    Design::Views::ParagraphStyles::Fields.new(paragraph_style: style, editable: true).call
  end

  def preview_render
    theme = Design::Theme.create!(name: "GP #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "title_page")
    Design::Views::DocumentDesigns::Preview.new(
      document_design: dd, paper_size: ps, jpg_url: "/x.jpg",
      overlay_data: [{ type: "heading_area", markup: "title", x: 0, y: 0, width: 50, height: 10 }],
      page_width: 100, page_height: 100, style_urls: {}
    ).call
  end

  def preview_error_render
    Design::Views::DocumentDesigns::PreviewError.new(error: "boom").call
  end

  def paragraph_panel_render
    theme = Design::Theme.create!(name: "GPN #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.find_by(doc_type: "chapter") || ps.document_designs.create!(doc_type: "chapter")
    theme.base_paragraph_styles.find_or_create_by!(name: "body").update!(font_size: 10)
    dd.set_style_field!("body", "font_size", 12) # so the chip, menu counts and × render
    c = Design::Views::ParagraphStyles::StylePanel.new(
      document_design: dd, style_name: "body", back_url: "/x",
      urls: { field: "/x", style: "/x", push: "/x", preview: "/x" })
    c.define_singleton_method(:helpers) { Object.new.tap { |o| def o.form_authenticity_token = "t" } }
    c.call
  end

  def paper_sizes_form_render
    theme = Design::Theme.create!(name: "GPS #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    base = theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    c = Design::Views::PaperSizes::Form.new(theme: theme, paper_size: ps, base_styles: [ base ])
    c.define_singleton_method(:helpers) do
      o = Object.new
      def o.theme_path(*) = "/x"
      def o.theme_paper_size_path(*) = "/x"
      def o.regenerate_theme_paper_size_path(*) = "/x"
      def o.edit_theme_paper_size_base_paragraph_style_path(*) = "/x"
      def o.form_authenticity_token = "t"
      o
    end
    # Re-housing this view in the Shell means its top bar now resolves
    # config.home_url. The default (`-> { main_app.root_path }`) needs a real
    # view context the Shell child component lacks in a pure unit render, so
    # pin a static home target for this render (test_helper restores config).
    Design.config.home_url = -> { "/" }
    # The form now renders the studio Sidebar as a child component, which calls
    # helpers.*_path on its OWN (nil) view context in a bare unit render. The rail
    # is a separate component excluded from this bare render; its localization is
    # guarded by Design::SidebarTest ("renders Korean labels with no
    # translation-missing leftovers", test/components/design/sidebar_test.rb).
    c.define_singleton_method(:sidebar) { nil }
    c.call
  end

  test "no English leftovers across unit-renderable components under :ko" do
    # Curated, SAFE glossary labels: distinctive English visible-label text that
    # must be translated under :ko and that does NOT collide with CSS classes,
    # HTML attributes, data-*, or intentional literals (CMYK/Hex/pt/mm/font
    # names/etc. are exempt). Intentionally excludes words like Color/Image/Name/
    # Top/Left/Border/Fill that appear inside markup attributes.
    deny = %w[
      Layout
      Typography
      Tracking
      Margins
      Generating
      Heading
    ]
    deny += [
      "Space Width",
      "Line Spacing",
      "Binding Margin",
      "Base Text Styles",
      "Revert to base",
      "New Style",
      "Generating preview",
      "Heading V-Align",
      "Body Line Count"
    ]

    renders = I18n.with_locale(:ko) do
      [
        panel_render,
        fields_render,
        preview_render,
        preview_error_render,
        paragraph_panel_render,
        paper_sizes_form_render
      ]
    end

    renders.each do |html|
      deny.each { |w| assert_not_includes html, w }
      assert_not_includes html, "translation missing"
    end
  end
end
