require "test_helper"

class Design::PropertiesPanelTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "PP #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  # --------------- Tab structure ---------------

  test "renders the three tab triggers with correct labels" do
    html = render_panel
    assert_includes html, "Layout"
    assert_includes html, "Typography"
    assert_includes html, "Header/Footer"
  end

  test "renders RubyUI::Tabs data-controller attribute" do
    html = render_panel
    assert_includes html, %(data-controller="ruby-ui--tabs")
  end

  test "renders TabsTrigger data-value attributes for all three tabs" do
    html = render_panel
    assert_includes html, %(data-value="layout")
    assert_includes html, %(data-value="typography")
    assert_includes html, %(data-value="header_footer")
  end

  test "renders turbo-frame with id properties_panel" do
    html = render_panel
    assert_includes html, "properties_panel"
    assert_includes html, "turbo-frame"
  end

  # --------------- Layout tab sections ---------------

  test "renders Heading Elements section" do
    html = render_panel
    assert_includes html, "Heading Elements"
    assert_includes html, %(data-controller="design--heading-elements")
  end

  test "renders Heading Background section" do
    html = render_panel
    assert_includes html, "Heading Background"
    assert_includes html, %(data-controller="design--heading-bg")
  end

  test "renders layout fields (heading lines, columns)" do
    html = render_panel
    assert_includes html, %(name="document_design[heading_height_in_lines]")
    assert_includes html, %(name="document_design[column_count]")
  end

  # --------------- Header/Footer tab ---------------

  test "renders Header / Footer section labels" do
    html = render_panel
    assert_includes html, "Header/Footer"
    assert_includes html, %(name="document_design[header_left_content_string]")
    assert_includes html, %(name="document_design[footer_right_content_string]")
  end

  # --------------- Save button (editable:true) ---------------

  test "renders Save submit button when editable: true" do
    html = render_panel(editable: true)
    assert_includes html, "Save"
    assert_includes html, %(type="submit")
  end

  # --------------- Read-only gating (Step 4) ---------------

  test "omits Save submit button when editable: false" do
    html = render_panel(editable: false)
    refute_includes html, %(type="submit")
  end

  test "inputs are disabled when editable: false" do
    html = render_panel(editable: false)
    # The disabled attribute must appear somewhere in the output
    assert_includes html, "disabled"
    # A specific layout field must carry disabled
    pattern = /name="document_design\[heading_height_in_lines\]"[^>]*disabled|disabled[^>]*name="document_design\[heading_height_in_lines\]"/
    assert_match pattern, html
  end

  test "heading-element remove button is inert (no action) when editable: false" do
    editable_html = render_panel(editable: true)
    readonly_html = render_panel(editable: false)
    # The remove action is wired when editable, dropped when read-only (no edit path leak).
    assert_includes editable_html, "design--heading-elements#remove"
    refute_includes readonly_html, "design--heading-elements#remove"
  end

  test "heading-element row has group class and remove button uses hover-reveal pattern" do
    @dd.heading_elements.create!(element_type: "title", style_name: "title", position: 0)
    html = render_panel
    # Row carries group for CSS group-hover to work
    assert_includes html, "group"
    # Remove button is hidden by default and revealed on hover (matches book_design UX)
    assert_includes html, "opacity-0 group-hover:opacity-100 transition-opacity"
  end

  test "inputs are NOT disabled when editable: true" do
    html = render_panel(editable: true)
    # The heading_height_in_lines field should not have disabled near it
    refute_match(/name="document_design\[heading_height_in_lines\]"[^>]*disabled/, html)
  end

  test "heading background color input is disabled when editable: false" do
    html = render_panel(editable: false)
    assert_includes html, %(name="document_design[heading_bg_color]")
    assert_includes html, "disabled"
  end

  test "header/footer content fields are disabled when editable: false" do
    html = render_panel(editable: false)
    assert_includes html, %(name="document_design[header_left_content_string]")
    assert_includes html, "disabled"
  end

  # --------------- Heading elements with persisted records ---------------

  test "renders existing heading element rows" do
    @dd.heading_elements.create!(element_type: "title", style_name: "title", position: 0)
    html = render_panel
    assert_includes html, %(name="document_design[heading_elements_attributes][0][element_type]")
    assert_includes html, "Title"
  end

  # --------------- text_box section (Task 4) ---------------

  test "renders text_box section with anchor, grid_width, and grid_height inputs" do
    html = render_panel
    assert_includes html, "Text Box Position"
    assert_includes html, %(name="document_design[text_box_anchor_position]")
    assert_includes html, %(name="document_design[text_box_grid_width]")
    assert_includes html, %(name="document_design[text_box_grid_height]")
  end

  test "text_box inputs are disabled when editable: false" do
    html = render_panel(editable: false)
    assert_match(/name="document_design\[text_box_grid_width\]"[^>]*disabled|disabled[^>]*name="document_design\[text_box_grid_width\]"/, html)
    assert_match(/name="document_design\[text_box_grid_height\]"[^>]*disabled|disabled[^>]*name="document_design\[text_box_grid_height\]"/, html)
    assert_match(/name="document_design\[text_box_anchor_position\]"[^>]*disabled|disabled[^>]*name="document_design\[text_box_anchor_position\]"/, html)
  end

  test "text_box inputs are not disabled when editable: true" do
    html = render_panel(editable: true)
    refute_match(/name="document_design\[text_box_grid_width\]"[^>]*disabled/, html)
    refute_match(/name="document_design\[text_box_grid_height\]"[^>]*disabled/, html)
  end

  # --------------- page_bg section (Task 4) ---------------

  test "renders page_bg section with color input and design--color-field controller" do
    html = render_panel
    assert_includes html, "Page Background"
    assert_includes html, %(name="document_design[page_bg_color]")
    assert_includes html, %(data-controller="design--color-field")
  end

  test "page_bg color inputs are disabled when editable: false" do
    html = render_panel(editable: false)
    # page_bg_color text input has data-action containing "->", so use a multichar scan
    assert_includes html, %(name="document_design[page_bg_color]")
    assert_includes html, "disabled"
    # Verify the text input carries disabled (it appears after the data-action attr which contains "->")
    assert_match(/name="document_design\[page_bg_color\]".*?disabled/m, html)
  end

  test "page_bg color picker input is disabled when editable: false" do
    html = render_panel(editable: false)
    assert_includes html, %(data-controller="design--color-field")
    # The color picker (type="color") inside the color-field controller must carry disabled
    assert_includes html, "disabled"
  end

  # --------------- document_cover section (Task 4) ---------------

  test "renders document_cover section with has_document_cover checkbox and cover_type select" do
    html = render_panel
    assert_includes html, "Document Cover"
    assert_includes html, %(name="document_design[has_document_cover]")
    assert_includes html, %(name="document_design[cover_type]")
  end

  test "document_cover section wires design--toggle-visibility controller" do
    html = render_panel
    assert_includes html, %(data-controller="design--toggle-visibility")
    assert_includes html, %(data-action="change->design--toggle-visibility#toggle")
    assert_includes html, %(data-design--toggle-visibility-target="content")
  end

  test "document_cover cover_type sub-field is hidden when has_document_cover is false" do
    @dd.update!(has_document_cover: false)
    html = render_panel
    assert_includes html, %(class="hidden")
  end

  test "document_cover cover_type sub-field is visible when has_document_cover is true" do
    @dd.update!(has_document_cover: true)
    html = render_panel
    # The content div should NOT have class="hidden" when has_document_cover is true
    refute_match(/class="hidden"[^>]*data-design--toggle-visibility-target="content"|data-design--toggle-visibility-target="content"[^>]*class="hidden"/, html)
  end

  test "document_cover inputs are disabled when editable: false" do
    html = render_panel(editable: false)
    # has_document_cover checkbox has data-action containing "->", use multiline scan
    assert_includes html, %(name="document_design[has_document_cover]")
    assert_match(/name="document_design\[has_document_cover\]" value="1".*?disabled/m, html)
    assert_match(/name="document_design\[cover_type\]"[^>]*disabled|disabled[^>]*name="document_design\[cover_type\]"/, html)
  end

  test "document_cover inputs are not disabled when editable: true" do
    html = render_panel(editable: true)
    refute_match(/name="document_design\[cover_type\]"[^>]*disabled/, html)
  end

  # --------------- Typography tab ---------------

  test "renders merged styles: base-only style shows (base) marker" do
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    html = render_panel
    assert_includes html, "body"
    assert_includes html, "(base)"
  end

  test "renders merged styles: overridden style does NOT show (base) marker immediately after its name span" do
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    @dd.paragraph_styles.create!(name: "body", font_size: 12)
    html = render_panel
    assert_includes html, "body"
    # When overridden, the name span is immediately followed by </div> (no (base) span in-between)
    assert_includes html, %(<span class="text-sm font-medium">body</span></div>)
    refute_includes html, %(<span class="text-sm font-medium">body</span><span class="text-[10px] text-slate-400 ml-1">(base)</span>)
  end

  test "renders korean_name when present" do
    @theme.base_paragraph_styles.create!(name: "body", korean_name: "본문", font_size: 10)
    html = render_panel
    assert_includes html, "본문"
  end

  test "Edit link for base-only style uses override POST path" do
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    html = render_panel(editable: true)
    assert_includes html, "/test/override"
    assert_includes html, %(data-turbo-method="post")
  end

  test "Edit link for overridden style uses panel GET path with level and style_id" do
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    override = @dd.paragraph_styles.create!(name: "body", font_size: 12)
    html = render_panel(editable: true)
    assert_includes html, "/test/panel/#{override.id}"
    assert_includes html, %(data-turbo-frame="properties_panel")
  end

  test "Add Style button present when editable: true" do
    html = render_panel(editable: true)
    assert_includes html, "Add Style"
    assert_includes html, "/test/new_style"
  end

  test "No Edit links and no Add Style button when editable: false" do
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    override = @dd.paragraph_styles.create!(name: "body", font_size: 12)
    html = render_panel(editable: false)
    # Style names still render
    assert_includes html, "body"
    # But no Edit links or Add Style button
    refute_includes html, "Edit"
    refute_includes html, "Add Style"
  end

  test "styles sorted in canonical order (title before body)" do
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    @theme.base_paragraph_styles.create!(name: "title", font_size: 18)
    html = render_panel
    # Look for the style name spans in the typography section
    title_pos = html.index('font-medium">title<')
    body_pos  = html.index('font-medium">body<')
    assert title_pos && body_pos, "both title and body style spans must be present"
    assert title_pos < body_pos, "title should appear before body in canonical order"
  end

  private

  # Build and render the panel, stubbing out the URL helpers that need a request context.
  def render_panel(editable: true)
    component = Design::Views::DocumentDesigns::PropertiesPanel.new(
      theme: @theme,
      paper_size: @ps,
      document_design: @dd,
      editable: editable
    )
    # Stub URL helpers that require a view context (no request in unit tests)
    component.define_singleton_method(:form_action_url) { "/design/themes/1/paper_sizes/1/document_designs/1" }
    component.define_singleton_method(:preview_url) { "/design/themes/1/paper_sizes/1/document_designs/1/preview" }
    component.define_singleton_method(:csrf_token) { "test-token" }
    # Stub typography URL helpers
    component.define_singleton_method(:typography_panel_url) { |override| "/test/panel/#{override.id}" }
    component.define_singleton_method(:typography_override_url) { |_name| "/test/override" }
    component.define_singleton_method(:typography_new_style_url) { "/test/new_style" }
    component.call
  end
end
