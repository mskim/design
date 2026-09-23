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

  test "the Page section is the Layout tab's first box; the tabs form no longer carries its fields" do
    doc = Nokogiri::HTML.fragment(render_panel)
    tabs_form = doc.at_css("form[data-controller~='design--live-preview']")
    section = tabs_form.at_css("[data-page-section]")
    assert section, "inside the tabs form (the Layout tab)"
    assert_nil section.previous_element, "the first box"
    assert_equal "basic", section.next_element["data-group"]
    names = tabs_form.css("[name^='document_design[']").map { |e| e["name"] }
    assert_includes names, "document_design[heading_height_in_lines]"
    %w[body_line_count column_count gutter].each { |f| refute_includes names, "document_design[#{f}]" }
    page_controls = tabs_form.css("[name^='page[']")
    refute_empty page_controls
    assert page_controls.all? { |e| e["form"] == "page-section-form" }, "FormData(tabs form) skips them"
  end

  test "the Page section's empty form sits outside the tabs form, inside the frame" do
    doc = Nokogiri::HTML.fragment(render_panel)
    form = doc.at_css("form#page-section-form")
    assert form
    assert_empty form.ancestors("form")
    assert form.ancestors("turbo-frame#properties_panel").any?
    assert_empty form.element_children
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

  # --------------- Object section (D4) ---------------

  test "copyright gets the Object section; the tabs form carries no text-box or photo fields" do
    @dd = @ps.document_designs.create!(doc_type: "copyright")
    doc = Nokogiri::HTML.fragment(render_panel)
    section = doc.at_css("[data-object-section]")
    assert section, "the Object section is in the Layout tab"
    assert_empty doc.css("[name^='document_design[text_box_']"), "copyright's box is the inspector's now"
    assert doc.css("[name^='object[']").all? { |e| e["form"] == "object-section-form" }
    form = doc.at_css("form#object-section-form")
    assert form && form.ancestors("form").empty? && form.ancestors("turbo-frame#properties_panel").any?
    assert_empty form.element_children
  end

  test "front_wing gets the Object section instead of the old photo box" do
    @dd = @ps.document_designs.create!(doc_type: "front_wing")
    doc = Nokogiri::HTML.fragment(render_panel)
    assert doc.at_css("[data-object-section]")
    assert_empty doc.css("[name^='document_design[photo_']")
  end

  test "front_page and seneca keep the plain text-box controls in the tabs form" do
    %w[front_page seneca].each do |doc_type|
      @dd = @ps.document_designs.create!(doc_type: doc_type)
      doc = Nokogiri::HTML.fragment(render_panel)
      assert_nil doc.at_css("[data-object-section]"), doc_type
      assert doc.at_css("select[name='document_design[text_box_anchor_position]']"), doc_type
      %w[text_box_grid_width text_box_grid_height].each do |f|
        assert doc.at_css("input[name='document_design[#{f}]']"), "#{doc_type} #{f}"
      end
    end
  end

  test "a doc type no renderer reads the fields for gets neither the inspector nor the plain controls" do
    doc = Nokogiri::HTML.fragment(render_panel) # chapter
    assert_nil doc.at_css("[data-object-section]")
    assert_empty doc.css("[name^='document_design[text_box_']")
    assert_nil doc.at_css("form#object-section-form"), "no section, no form"
  end

  test "the plain text-box controls are disabled when editable: false" do
    @dd = @ps.document_designs.create!(doc_type: "seneca")
    html = render_panel(editable: false)
    %w[text_box_anchor_position text_box_grid_width text_box_grid_height].each do |f|
      assert_match(/name="document_design\[#{f}\]"[^>]*disabled|disabled[^>]*name="document_design\[#{f}\]"/, html, f)
    end
  end

  # --------------- page_bg section (Task 4) ---------------

  COLOR_ATTRS = %w[page_bg_color heading_bg_color heading_bg_gradient_start heading_bg_gradient_end].freeze

  test "renders page_bg section with color input and design--color-row controller" do
    html = render_panel
    assert_includes html, "Page Background"
    doc = Nokogiri::HTML.fragment(html)
    assert doc.at_css("[data-controller='design--color-row'] input[type=hidden][name='document_design[page_bg_color]']"),
           "page_bg_color must be a hidden input inside design--color-row"
    assert_includes html, I18n.t("design.properties_panel.page_background_hint")
  end

  test "every colour field is a hidden input inside a design--color-row" do
    @dd = @ps.document_designs.create!(doc_type: "front_wing")
    doc = Nokogiri::HTML.fragment(render_panel)
    COLOR_ATTRS.each do |attr|
      assert doc.at_css("[data-controller='design--color-row'] input[type=hidden][name='document_design[#{attr}]']"),
             "#{attr} must be a hidden input inside design--color-row"
    end
    assert_empty doc.css("[data-controller='design--color-field'], [data-controller='design--color-mode-field']")
    assert_empty doc.css("input[type=color][name]"), "no native colour picker may submit a value"
  end

  test "gradient colour rows are hex-only and keep their defaults" do
    doc = Nokogiri::HTML.fragment(render_panel)
    { "heading_bg_gradient_start" => "#ffffff", "heading_bg_gradient_end" => "#000000" }.each do |attr, default|
      hidden = doc.at_css("input[name='document_design[#{attr}]']")
      assert_equal default, hidden["value"]
      row = hidden.ancestors("[data-controller='design--color-row']").first
      assert_equal "hex", row["data-design--color-row-formats-value"]
    end
    assert_equal "white", doc.at_css("input[name='document_design[heading_bg_color]']")["value"]
  end

  test "page_bg color inputs are disabled when editable: false" do
    doc = Nokogiri::HTML.fragment(render_panel(editable: false))
    hidden = doc.at_css("[data-controller='design--color-row'] input[type=hidden][name='document_design[page_bg_color]']")
    assert hidden
    assert hidden.key?("disabled"), "page_bg_color hidden input must be disabled"
  end

  test "colour row trigger buttons are disabled when editable: false" do
    @dd = @ps.document_designs.create!(doc_type: "front_wing")
    doc = Nokogiri::HTML.fragment(render_panel(editable: false))
    COLOR_ATTRS.each do |attr|
      row = doc.at_css("input[name='document_design[#{attr}]']").ancestors("[data-controller='design--color-row']").first
      trigger = row.at_css("button[data-design--color-row-target='trigger']")
      assert trigger.key?("disabled"), "#{attr} trigger must be disabled"
    end
  end

  test "colour row trigger buttons are enabled when editable: true" do
    @dd = @ps.document_designs.create!(doc_type: "front_wing")
    doc = Nokogiri::HTML.fragment(render_panel(editable: true))
    COLOR_ATTRS.each do |attr|
      row = doc.at_css("input[name='document_design[#{attr}]']").ancestors("[data-controller='design--color-row']").first
      refute row.at_css("button[data-design--color-row-target='trigger']").key?("disabled"), "#{attr} trigger must be enabled"
    end
  end

  # --------------- Number fields (design--scrub-input) ---------------

  test "the photo's cell width is a scrub-input number field capped at 6" do
    @dd = @ps.document_designs.create!(doc_type: "front_wing")
    doc = Nokogiri::HTML.fragment(render_panel)
    input = doc.at_css("[data-controller='design--scrub-input'] input[name='object[photo_grid_width]']")
    assert input, "photo_grid_width must be inside design--scrub-input"
    assert_equal "6", input.ancestors("[data-controller='design--scrub-input']").first["data-design--scrub-input-max-value"]
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

  test "a style changed on this doc type shows +; an inherited one doesn't; no (base) marker" do
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    @theme.base_paragraph_styles.create!(name: "caption", font_size: 8)
    @dd.set_style_field!("body", "font_size", 12)
    doc = Nokogiri::HTML.fragment(render_panel)
    assert doc.at_css("[data-style-row='body'] [data-changed-marker]")
    assert_nil doc.at_css("[data-style-row='caption'] [data-changed-marker]")
    refute_includes doc.to_html, "(base)"
  end

  test "renders korean_name when present" do
    @theme.base_paragraph_styles.create!(name: "body", korean_name: "본문", font_size: 10)
    html = render_panel
    assert_includes html, "본문"
  end

  test "Edit links open the name-keyed style panel in the properties_panel frame (no POST override)" do
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    html = render_panel(editable: true)
    assert_includes html, %(href="/test/styles/body")
    assert_includes html, %(data-turbo-frame="properties_panel")
    refute_includes html, %(data-turbo-method="post")
  end

  test "Add Style button present when editable: true" do
    html = render_panel(editable: true)
    assert_includes html, "Add Style"
    assert_includes html, "/test/new_style"
  end

  test "No Edit links and no Add Style button when editable: false" do
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    html = render_panel(editable: false)
    assert_includes html, "body"
    refute_includes html, "/test/styles/"
    refute_includes html, "/test/new_style"
  end

  test "tab: typography opens the 단락정의 tab; anything else opens 레이아웃" do
    assert_includes render_panel(tab: "typography"), %(data-ruby-ui--tabs-active-value="typography")
    assert_includes render_panel(tab: "bogus"), %(data-ruby-ui--tabs-active-value="layout")
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
  def render_panel(editable: true, tab: nil)
    component = Design::Views::DocumentDesigns::PropertiesPanel.new(
      theme: @theme,
      paper_size: @ps,
      document_design: @dd,
      editable: editable,
      tab: tab
    )
    # Stub URL helpers that require a view context (no request in unit tests)
    component.define_singleton_method(:form_action_url) { "/design/themes/1/paper_sizes/1/document_designs/1" }
    component.define_singleton_method(:preview_url) { "/design/themes/1/paper_sizes/1/document_designs/1/preview" }
    component.define_singleton_method(:csrf_token) { "test-token" }
    # Stub typography URL helpers
    component.define_singleton_method(:typography_style_url) { |name| "/test/styles/#{name}" }
    component.define_singleton_method(:typography_new_style_url) { "/test/new_style" }
    component.define_singleton_method(:page_urls) { { field: "/x/page/field", preview: "/x/preview", paper_size: "/x/ps/edit" } }
    component.define_singleton_method(:object_urls) { { field: "/x/object/field", preview: "/x/preview" } }
    component.call
  end
end
