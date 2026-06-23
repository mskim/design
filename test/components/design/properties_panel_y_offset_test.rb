require "test_helper"

class Design::PropertiesPanelYOffsetTest < ActiveSupport::TestCase
  def render_panel(doc_type: "chapter")
    theme = Design::Theme.create!(name: "YO #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: doc_type)
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

  test "header/footer tab renders the 4 y_offset inputs" do
    html = render_panel
    %w[header_left_y_offset header_right_y_offset footer_left_y_offset footer_right_y_offset].each do |attr|
      assert_includes html, %(name="document_design[#{attr}]"), "missing #{attr} input"
    end
  end

  test "header/footer tab still renders the 4 content_string inputs" do
    html = render_panel
    %w[header_left_content_string header_right_content_string footer_left_content_string footer_right_content_string].each do |attr|
      assert_includes html, %(name="document_design[#{attr}]"), "missing #{attr} input"
    end
  end
end
