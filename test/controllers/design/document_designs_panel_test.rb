require "test_helper"

class Design::DocumentDesignsPanelTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "PP #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  test "edit right pane is a properties_panel frame holding the tabbed PropertiesPanel form" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "turbo-frame#properties_panel form[data-controller~='design--live-preview']"
    assert_select "[data-controller~='ruby-ui--tabs']"
  end

  test "properties_panel endpoint renders the tabbed PropertiesPanel frame" do
    get design.properties_panel_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "turbo-frame#properties_panel form[data-controller~='design--live-preview']"
    assert_select "[data-controller~='ruby-ui--tabs']"
  end

  test "panel renders the autosave Panel for a theme-level style" do
    theme_style = @theme.base_paragraph_styles.create!(name: "body")
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id)
    assert_response :success
    assert_select "turbo-frame#properties_panel form[data-controller~='design--panel-autosave']"
    assert_includes response.body, %(name="paragraph_style[font_size]")
  end

  test "panel full navigation (preview click) renders a full page with preview on the left" do
    theme_style = @theme.base_paragraph_styles.create!(name: "body")
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id)
    assert_response :success
    # Full page: the document preview AND the style's edit form.
    assert_select "turbo-frame#preview_frame"
    assert_select "turbo-frame#properties_panel form[data-controller~='design--panel-autosave']"
  end

  test "panel as a turbo-frame request renders only the bare panel (embedded, no preview)" do
    theme_style = @theme.base_paragraph_styles.create!(name: "body")
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_response :success
    assert_select "turbo-frame#properties_panel"
    assert_select "turbo-frame#preview_frame", count: 0
  end

  test "panel_update at level=theme redirects the edit to doc_type overrides and leaves the base untouched" do
    theme_style = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    begin
      patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id),
            params: { paragraph_style: { font_size: 18 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    ensure
      Design::PreviewService.define_singleton_method(:new, original)
    end
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, "preview_frame"
    assert_equal 10.0, theme_style.reload.font_size, "theme base not mutated; edit redirected to doc_type overrides"
    assert_equal 18.0, @dd.paragraph_styles.find_by(name: "body").font_size, "current doc_type gets the override"
  end

  # ── Edit-in-place across ALL 3 levels (verification additions) ──

  def stub_preview
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.define_singleton_method(:new, original)
  end

  test "panel_update at level=paper redirects the edit to doc_type overrides and leaves the paper record untouched" do
    paper_style = @ps.paragraph_styles.create!(name: "caption", font_size: 9)
    stub_preview do
      patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "paper", style_id: paper_style.id),
            params: { paragraph_style: { font_size: 14 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, "preview_frame"
    assert_equal 9.0, paper_style.reload.font_size, "paper-level record not mutated; redirected to doc_type overrides"
    assert_equal 14.0, @dd.paragraph_styles.find_by(name: "caption").font_size, "current doc_type gets the override"
  end

  test "panel_update at level=document updates the document-design style record" do
    doc_style = @dd.paragraph_styles.create!(name: "quote", font_size: 11)
    stub_preview do
      patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: doc_style.id),
            params: { paragraph_style: { font_size: 22 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, "preview_frame"
    assert_equal 22.0, doc_style.reload.font_size
  end

  test "panel_update does not cross levels: a document style id is not found at theme level (nothing saved)" do
    doc_style = @dd.paragraph_styles.create!(name: "quote2", font_size: 11)
    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: doc_style.id),
          params: { paragraph_style: { font_size: 22 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="properties_panel">}, response.body
    assert_equal 11.0, doc_style.reload.font_size
  end

  test "invalid level raises RecordNotFound (404)" do
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "bogus", style_id: 1)
    assert_response :not_found
  end

  test "panel_update re-renders Panel at 422 on validation failure" do
    theme_style = @theme.base_paragraph_styles.create!(name: "valid", font_size: 10)
    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id),
          params: { paragraph_style: { name: "" } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :unprocessable_entity
    assert_select "turbo-frame#properties_panel form[data-controller~='design--panel-autosave']"
  end

  # Revert ("기본값으로 되돌리기") should appear whenever THIS document already has an
  # override of the style being edited — even when the style was opened at the base
  # (theme) level — so an override created by a default-scope save can be undone here.
  test "panel shows revert for a base style that already has a document override" do
    base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    @dd.paragraph_styles.create!(name: "body", font_size: 12) # document override exists

    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: base.id),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_response :success
    assert_select "a[href*=?][data-turbo-method=delete]", "/revert", { count: 1 }, "revert link should be present"
  end

  test "panel hides revert for a base style with no document override" do
    base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)

    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: base.id),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_response :success
    assert_select "a[href*=?]", "/revert", { count: 0 }, "no revert when nothing is overridden"
  end

  test "writer forbidden from panel" do
    sign_in :kevin
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: 1)
    assert_response :forbidden
  end

  test "writer forbidden from panel_update" do
    sign_in :kevin
    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: 1),
          params: { paragraph_style: { font_size: 5 } }
    assert_response :forbidden
  end

  test "panel_update without apply_scope fans out to same-doc_type designs and leaves base" do
    s2 = @theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
    ch2 = s2.document_designs.create!(doc_type: "chapter")
    base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)

    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: base.id),
          params: { paragraph_style: { font_size: 13 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "13.0", @dd.paragraph_styles.find_by(name: "body").font_size.to_s
    assert_equal "13.0", ch2.paragraph_styles.find_by(name: "body").font_size.to_s
    assert_equal 10, base.reload.font_size, "base untouched on scoped save"
  end

  # What a browser posts for the style Panel, derived by rendering the panel (at
  # `level`, for `style`) and reading its form: disabled controls are skipped; a
  # select posts its selected option, else its blank option, else its first; a
  # checkbox posts only when checked (after any same-name hidden field, as Rails
  # emits them); other inputs post their value or "". `edits` override the
  # paragraph_style[<field>] values (as a user typing would); `extra` sets other
  # top-level params (e.g. apply_scope: "all", as ticking the checkbox would).
  def form_params_for(style, level:, dd: @dd, theme: @theme, ps: @ps, extra: {}, **edits)
    get design.panel_theme_paper_size_document_design_path(theme, ps, dd, level: level, style_id: style.id),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_response :success
    form = Nokogiri::HTML5(response.body).at_css("turbo-frame#properties_panel form")
    pairs = form.css("input[name], select[name], textarea[name]").filter_map do |el|
      next if el.key?("disabled")
      [ el["name"], browser_value(el) ].then { |pair| pair[1].nil? ? nil : pair }
    end
    edits.each do |field, value|
      key = "paragraph_style[#{field}]"
      assert pairs.any? { |k, _| k == key }, "the form has no enabled #{key}"
      pairs = pairs.map { |k, v| k == key ? [ k, value.to_s ] : [ k, v ] }
    end
    pairs += extra.map { |k, v| [ k.to_s, v.to_s ] }
    Rack::Utils.parse_nested_query(URI.encode_www_form(pairs.reject { |k, _| k == "_method" }))
  end

  # The value a browser submits for one control, or nil when it submits none.
  def browser_value(el)
    case el.name
    when "select"
      opt = el.at_css("option[selected]") || el.css("option").find { |o| o["value"] == "" } || el.at_css("option")
      opt && (opt["value"] || opt.text)
    when "textarea" then el.text
    else
      case el["type"]
      when "checkbox", "radio" then el.key?("checked") ? (el["value"] || "on") : nil
      when "submit", "button", "image", "file" then nil
      else el["value"].to_s
      end
    end
  end

  def panel_update_path_for(style, level:, dd: @dd, theme: @theme, ps: @ps)
    design.panel_update_theme_paper_size_document_design_path(theme, ps, dd, level: level, style_id: style.id)
  end

  def turbo_stream_headers = { "Accept" => "text/vnd.turbo-stream.html" }

  test "default-scope save where only font_size changed leaves every other field nil on all sizes" do
    s2 = @theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
    ch2 = s2.document_designs.find_or_create_by!(doc_type: "chapter")
    base = @theme.base_paragraph_styles.create!(name: "body", font: "BaseFont", font_size: 10,
                                                text_align: "justify", text_color: "CMYK=0,0,0,100", first_line_indent: 10)

    params = form_params_for(base, level: "theme", font_size: 13)
    stub_preview do
      patch panel_update_path_for(base, level: "theme"), params: params, headers: turbo_stream_headers
    end

    assert_response :success
    [ @dd, ch2 ].each do |ch|
      row = ch.paragraph_styles.find_by(name: "body")
      assert_not_nil row&.font_size, "font_size written on #{ch.paper_size.size_name}"
      (Design::ParagraphStyle::STYLE_FIELDS - %w[font_size]).each do |f|
        assert_nil row[f], "#{f} was not changed, so it stays inherited on #{ch.paper_size.size_name}"
      end
    end
  end

  test "default-scope save that doesn't touch font_size keeps per-size scaled heading sizes" do
    theme = Design::Theme.create!(name: "PH #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    theme.base_paragraph_styles.create!(name: "title", font: "BaseFont", font_size: 24)
    big = theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    small = theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
    ch_big = big.document_designs.find_or_create_by!(doc_type: "chapter")
    ch_small = small.document_designs.find_or_create_by!(doc_type: "chapter")
    big_title = ch_big.paragraph_styles.find_by!(name: "title")
    small_size = ch_small.paragraph_styles.find_by!(name: "title").font_size
    refute_equal big_title.font_size, small_size, "precondition: the generator scaled title per size"

    params = form_params_for(big_title, level: "document", dd: ch_big, theme: theme, ps: big, text_color: "CMYK=0,100,0,0")
    stub_preview do
      patch panel_update_path_for(big_title, level: "document", dd: ch_big, theme: theme, ps: big),
            params: params, headers: turbo_stream_headers
    end

    assert_response :success
    small_row = ch_small.paragraph_styles.find_by!(name: "title")
    assert_equal small_size, small_row.font_size, "the other size keeps its own scaled heading size"
    assert_equal "CMYK=0,100,0,0", small_row.text_color, "the changed field fans out"
    assert_equal "CMYK=0,100,0,0", big_title.reload.text_color
  end

  test "default-scope save refreshes the panel as the document override with a revert link" do
    base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)

    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: base.id),
          params: { paragraph_style: { name: "body", font_size: 13 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="preview_frame">}, response.body
    assert_match %r{<turbo-stream action="replace" target="properties_panel">}, response.body
    override = @dd.paragraph_styles.find_by(name: "body")
    # the refreshed panel now edits the override (level=document) and offers revert
    assert_match %r{level=document&(amp;)?style_id=#{override.id}}, response.body
    assert_match %r{paragraph_styles/#{override.id}/revert}, response.body
  end

  test "apply_scope=all save refreshes the panel as the base style (no revert)" do
    base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    @dd.paragraph_styles.create!(name: "body", font_size: 8)

    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: @dd.paragraph_styles.find_by(name: "body").id),
          params: { paragraph_style: { name: "body", font_size: 22 }, apply_scope: "all" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="properties_panel">}, response.body
    assert_match %r{level=theme&(amp;)?style_id=#{base.id}}, response.body
    refute_match %r{/revert}, response.body, "base style has no override to revert"
  end

  test "panel_update with apply_scope=all writes the base and clears overrides" do
    base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    @dd.paragraph_styles.create!(name: "body", font_size: 8)

    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: base.id),
          params: { paragraph_style: { font_size: 22 }, apply_scope: "all" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal 22, base.reload.font_size
    assert_equal 0, @dd.paragraph_styles.where(name: "body").count, "shadow override cleared"
  end

  # A style link can outlive its override (Revert to base, or an "apply to all"
  # save that clears overrides, leaves stale preview-overlay / browser-back links).
  # Following such a link must degrade gracefully, not 500.
  test "panel for a destroyed document override redirects to the editor (full navigation)" do
    override = @dd.paragraph_styles.create!(name: "title", font_size: 20)
    gone_id = override.id
    override.destroy

    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: gone_id)
    assert_redirected_to design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
  end

  test "panel for a destroyed document override re-renders the properties panel (turbo-frame)" do
    override = @dd.paragraph_styles.create!(name: "title", font_size: 20)
    gone_id = override.id
    override.destroy

    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: gone_id),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_response :success
    assert_select "turbo-frame#properties_panel"
  end

  test "panel_update for a destroyed document override refreshes the panel to the base style (not a 404)" do
    base = @theme.base_paragraph_styles.create!(name: "zz_gone", font_size: 10)
    override = @dd.paragraph_styles.create!(name: "zz_gone", font_size: 20)
    gone_id = override.id
    override.destroy

    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: gone_id),
          params: { paragraph_style: { name: "zz_gone", font_size: 13 } },
          headers: turbo_stream_headers
    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="properties_panel">}, response.body
    assert_match %r{level=theme&(amp;)?style_id=#{base.id}}, response.body
    assert_equal 10, base.reload.font_size, "a stale Save writes nothing"
    assert_nil @dd.paragraph_styles.find_by(name: "zz_gone")
  end

  test "panel_update for a destroyed row with no base falls back to the design view" do
    override = @dd.paragraph_styles.create!(name: "zz_orphan", font_size: 20)
    gone_id = override.id
    override.destroy

    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: gone_id),
          params: { paragraph_style: { name: "zz_orphan", font_size: 13 } },
          headers: turbo_stream_headers
    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="properties_panel">}, response.body
    assert_includes response.body, "design--live-preview", "the design's own properties panel"
  end

  test "panel_update with an unknown level still 404s" do
    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "bogus", style_id: 1),
          params: { paragraph_style: { font_size: 13 } }, headers: turbo_stream_headers
    assert_response :not_found
  end

  # ── Browser-accurate Saves (form params derived from the rendered panel) ──

  test "apply_scope=all from a sparse document row writes only the changed field to the base" do
    base = @theme.base_paragraph_styles.create!(name: "zz_body", font: "BaseFont", font_size: 10, text_align: "justify")
    row = @dd.paragraph_styles.create!(name: "zz_body", font_size: 12, text_align: "left",
                                       overridden_fields: %w[font_size text_align])
    poem = @ps.document_designs.create!(doc_type: "poem")
    poem.paragraph_styles.create!(name: "zz_body", text_color: "CMYK=0,0,100,0", tracking: 1,
                                  overridden_fields: %w[text_color tracking])

    params = form_params_for(row, level: "document", text_color: "CMYK=0,100,0,0", extra: { apply_scope: "all" })
    stub_preview do
      patch panel_update_path_for(row, level: "document"), params: params, headers: turbo_stream_headers
    end

    assert_response :success
    base.reload
    assert_equal "BaseFont", base.font, "the sparse form's blank font must not wipe the base"
    assert_equal 10, base.font_size.to_i, "an unchanged font_size stays"
    assert_equal "justify", base.text_align
    assert_equal "CMYK=0,100,0,0", base.text_color, "the changed field moves to the base"
    assert_equal 12, row.reload.font_size.to_i, "other overrides are kept"
    assert_equal "left", row.text_align
    poem_row = poem.paragraph_styles.find_by(name: "zz_body")
    assert_nil poem_row.text_color, "the changed field is cleared on every doc-type row"
    refute_includes poem_row.overridden_fields, "text_color"
    assert_equal 1, poem_row.tracking.to_i
  end

  test "apply_scope=all clears a row whose only override was the changed field" do
    @theme.base_paragraph_styles.create!(name: "zz_body", font: "BaseFont", font_size: 10)
    row = @dd.paragraph_styles.create!(name: "zz_body", font_size: 12, overridden_fields: %w[font_size])

    params = form_params_for(row, level: "document", font_size: 14, extra: { apply_scope: "all" })
    stub_preview do
      patch panel_update_path_for(row, level: "document"), params: params, headers: turbo_stream_headers
    end

    assert_equal 14, @theme.base_paragraph_styles.find_by(name: "zz_body").font_size.to_i
    assert_nil @dd.paragraph_styles.find_by(name: "zz_body")
  end

  test "a document-level Save doesn't pin a select inherited from chapter (fill_type)" do
    @theme.base_paragraph_styles.create!(name: "zz_box", font: "BaseFont", font_size: 10)
    s2 = @theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
    [ @ps, s2 ].each do |ps|
      ch = ps.document_designs.find_or_create_by!(doc_type: "chapter")
      ch.paragraph_styles.create!(name: "zz_box", fill_type: "gradient", overridden_fields: %w[fill_type])
    end
    forewords = [ @ps, s2 ].map { |ps| ps.document_designs.create!(doc_type: "foreword") }
    forewords.each { |fw| fw.paragraph_styles.create!(name: "zz_box", font_size: 11, overridden_fields: %w[font_size]) }
    row = forewords.first.paragraph_styles.find_by!(name: "zz_box")

    params = form_params_for(row, level: "document", dd: forewords.first, text_color: "CMYK=0,100,0,0")
    assert_equal "", params.dig("paragraph_style", "fill_type"), "an inherited select posts its blank option"
    stub_preview do
      patch panel_update_path_for(row, level: "document", dd: forewords.first), params: params, headers: turbo_stream_headers
    end

    assert_response :success
    forewords.each do |fw|
      r = fw.paragraph_styles.find_by!(name: "zz_box")
      assert_nil r.fill_type, "fill_type stays inherited on #{fw.paper_size.size_name}"
      assert_equal "CMYK=0,100,0,0", r.text_color
      assert_equal 11, r.font_size.to_i
      (Design::ParagraphStyle::STYLE_FIELDS - %w[text_color font_size]).each do |f|
        assert_nil r[f], "#{f} untouched on #{fw.paper_size.size_name}"
      end
    end
  end

  test "a document-level Save that edits only text_color leaves every other field nil on all sizes" do
    @theme.base_paragraph_styles.create!(name: "zz_body", font: "BaseFont", font_size: 10, text_align: "justify",
                                         fill_type: "solid", corner_radius: "small", border_side: "top")
    s2 = @theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
    ch2 = s2.document_designs.find_or_create_by!(doc_type: "chapter")
    row = @dd.paragraph_styles.create!(name: "zz_body", space_after: 3, overridden_fields: %w[space_after])
    ch2.paragraph_styles.create!(name: "zz_body", space_after: 3, overridden_fields: %w[space_after])

    params = form_params_for(row, level: "document", text_color: "CMYK=0,100,0,0")
    stub_preview do
      patch panel_update_path_for(row, level: "document"), params: params, headers: turbo_stream_headers
    end

    assert_response :success
    [ @dd, ch2 ].each do |ch|
      r = ch.paragraph_styles.find_by!(name: "zz_body")
      assert_equal "CMYK=0,100,0,0", r.text_color
      (Design::ParagraphStyle::STYLE_FIELDS - %w[text_color space_after]).each do |f|
        assert_nil r[f], "#{f} untouched on #{ch.paper_size.size_name}"
      end
    end
  end

  test "reverting the last override re-renders the panel at the theme base, and the next Save works" do
    base = @theme.base_paragraph_styles.create!(name: "zz_body", font: "BaseFont", font_size: 10)
    row = @dd.paragraph_styles.create!(name: "zz_body", font_size: 12, overridden_fields: %w[font_size])

    params = form_params_for(row, level: "document", font_size: 10)
    stub_preview do
      patch panel_update_path_for(row, level: "document"), params: params, headers: turbo_stream_headers
    end
    assert_response :success
    assert_nil @dd.paragraph_styles.find_by(name: "zz_body"), "equal to the parent → the row is gone"
    assert_match %r{level=theme&(amp;)?style_id=#{base.id}}, response.body, "the panel now edits the base"

    params = form_params_for(base, level: "theme", font_size: 13)
    stub_preview do
      patch panel_update_path_for(base, level: "theme"), params: params, headers: turbo_stream_headers
    end
    assert_response :success
    assert_equal 13, @dd.paragraph_styles.find_by!(name: "zz_body").font_size.to_i
  end

  test "korean_name and vertical_align are read-only (not posted) at level=document" do
    @theme.base_paragraph_styles.find_or_create_by!(name: "table_body_cell")
    row = @dd.paragraph_styles.find_or_create_by!(name: "table_body_cell")

    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: row.id),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_select "input[name='paragraph_style[korean_name]'][disabled]"
    assert_select "select[name='paragraph_style[vertical_align]'][disabled]"
    assert_includes response.body, I18n.t("design.fields.theme_only_hint")

    params = form_params_for(row, level: "document")
    refute params["paragraph_style"].key?("korean_name")
    refute params["paragraph_style"].key?("vertical_align")
  end

  test "korean_name stays editable at level=theme" do
    base = @theme.base_paragraph_styles.create!(name: "zz_body", font_size: 10)
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: base.id),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_select "input[name='paragraph_style[korean_name]']:not([disabled])"
  end

  test "a select keeps a current value that isn't among its options" do
    base = @theme.base_paragraph_styles.create!(name: "zz_body", font: "SomeHouseFont", font_size: 10)
    params = form_params_for(base, level: "theme")
    assert_equal "SomeHouseFont", params.dig("paragraph_style", "font")
  end
end
