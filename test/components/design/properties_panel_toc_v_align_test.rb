require "test_helper"

class Design::PropertiesPanelTocVAlignTest < ActiveSupport::TestCase
  def render_panel(doc_type:, toc_v_align: nil)
    theme = Design::Theme.create!(name: "PP #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: doc_type, toc_v_align: toc_v_align)
    component = Design::Views::DocumentDesigns::PropertiesPanel.new(
      theme: theme, paper_size: ps, document_design: dd, editable: true
    )
    # Stub URL helpers that require a view context (no request in unit tests)
    component.define_singleton_method(:form_action_url) { "/design/themes/1/paper_sizes/1/document_designs/1" }
    component.define_singleton_method(:preview_url) { "/design/themes/1/paper_sizes/1/document_designs/1/preview" }
    component.define_singleton_method(:csrf_token) { "test-token" }
    component.define_singleton_method(:typography_panel_url) { |override| "/test/panel/#{override.id}" }
    component.define_singleton_method(:typography_override_url) { |_name| "/test/override" }
    component.define_singleton_method(:typography_new_style_url) { "/test/new_style" }
    component.call
  end

  test "TOC doc renders the toc_v_align select with persisted value selected" do
    html = render_panel(doc_type: "toc", toc_v_align: "center")
    assert_includes html, %(name="document_design[toc_v_align]")
    assert_includes html, "center"
  end

  test "non-TOC doc does not render the toc_v_align select" do
    html = render_panel(doc_type: "chapter")
    refute_includes html, %(name="document_design[toc_v_align]")
  end
end
