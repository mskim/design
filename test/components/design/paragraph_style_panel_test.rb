require "test_helper"

class Design::ParagraphStylePanelTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "PT #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
    @style = @dd.paragraph_styles.create!(name: "body", font_size: 10)
  end

  # ── Back link ──

  test "renders a back link to the full edit page, breaking out of the frame (_top)" do
    html = render_panel(@style)
    assert_includes html, "Back"
    assert_includes html, %(data-turbo-frame="_top")
    assert_includes html, "/test/back"
  end

  # ── Error alert ──

  test "renders error messages when style has errors" do
    @style.errors.add(:name, "can't be blank")
    html = render_panel(@style)
    assert_includes html, "Please fix the following errors"
    # Phlex HTML-encodes apostrophes; check for the encoded form
    assert_includes html, "Name can&#39;t be blank"
  end

  test "does NOT render error section when there are no errors" do
    html = render_panel(@style)
    refute_includes html, "Please fix the following errors"
  end

  # ── Revert link ──

  test "renders Revert link when revert_url given and editable: true" do
    html = render_panel(@style, revert_url: "/test/revert", editable: true)
    assert_includes html, "Revert"
    assert_includes html, "/test/revert"
    assert_includes html, %(data-turbo-method="delete")
    assert_includes html, %(data-turbo-frame="properties_panel")
  end

  test "does NOT render Revert link when revert_url is nil" do
    html = render_panel(@style, revert_url: nil, editable: true)
    refute_includes html, "Revert"
  end

  test "does NOT render Revert link when editable: false (even if revert_url present)" do
    html = render_panel(@style, revert_url: "/test/revert", editable: false)
    refute_includes html, "Revert"
  end

  # ── Save button ──

  test "renders Save submit button when editable: true" do
    html = render_panel(@style, editable: true)
    assert_includes html, "Save"
    assert_includes html, %(type="submit")
  end

  test "does NOT render Save submit button when editable: false" do
    html = render_panel(@style, editable: false)
    refute_includes html, %(type="submit")
    refute_includes html, "Save"
  end

  # ── Fields integration ──

  test "renders Fields component (font_size input present)" do
    html = render_panel(@style)
    assert_includes html, %(name="paragraph_style[font_size]")
  end

  test "renders Fields border-side and corner widgets" do
    html = render_panel(@style)
    assert_includes html, %(data-controller="design--border-side-editor")
    assert_includes html, %(data-controller="design--corner-editor")
  end

  # ── Read-only threading via Panel ──

  test "editable: false — Panel forwards disabled to Fields (font_size carries disabled)" do
    html = render_panel(@style, editable: false)
    assert_match(/name="paragraph_style\[font_size\]"[^>]*disabled|disabled[^>]*name="paragraph_style\[font_size\]"/, html)
  end

  test "editable: false — border-side-editor buttons carry disabled" do
    html = render_panel(@style, editable: false)
    assert_includes html, %(data-controller="design--border-side-editor")
    assert_match(/click->design--border-side-editor#toggle[^>]*disabled|disabled[^>]*click->design--border-side-editor#toggle/, html)
  end

  test "editable: false — corner-editor buttons carry disabled" do
    html = render_panel(@style, editable: false)
    assert_includes html, %(data-controller="design--corner-editor")
    assert_match(/click->design--corner-editor#toggle[^>]*disabled|disabled[^>]*click->design--corner-editor#toggle/, html)
  end

  test "editable: true — font_size input is NOT disabled" do
    html = render_panel(@style, editable: true)
    refute_match(/name="paragraph_style\[font_size\]"[^>]*disabled/, html)
  end

  test "editable: true — border-side-editor buttons are NOT disabled" do
    html = render_panel(@style, editable: true)
    refute_match(/click->design--border-side-editor#toggle[^>]*disabled/, html)
  end

  # ── Turbo frame wrapper ──

  test "wraps output in turbo-frame#properties_panel" do
    html = render_panel(@style)
    assert_includes html, "turbo-frame"
    assert_includes html, "properties_panel"
  end

  # ── New (unsaved) style: no _method patch ──

  test "new unsaved style: form uses POST (no _method patch hidden field)" do
    new_style = @dd.paragraph_styles.new
    html = render_panel(new_style, revert_url: nil)
    # A new/unsaved style should NOT inject _method=patch
    refute_includes html, %(value="patch")
  end

  test "persisted style: form injects _method=patch" do
    html = render_panel(@style)
    assert_includes html, %(value="patch")
  end

  test "renders the apply-to-all checkbox with shadow count when document_design is supplied" do
    theme = Design::Theme.create!(name: "PV #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")
    style = theme.base_paragraph_styles.create!(name: "body")

    html = render_panel(style, document_design: dd, save_scope_shadow_count: 2)

    assert_includes html, %(name="apply_scope")
    assert_includes html, %(value="all")
    assert_includes html, "design--save-scope"
    assert_includes html, %(data-design--save-scope-count-value="2")
    assert_match %r{data-controller="design--panel-autosave design--save-scope"}, html
    # The confirm message is interpolated server-side with the count (locale-agnostic check).
    assert_match %r{data-design--save-scope-message-value="2[^"]*"}, html
  end

  test "omits the checkbox when no document_design is supplied" do
    style = Design::ParagraphStyle.new(name: "body")
    html = render_panel(style)
    refute_includes html, %(name="apply_scope")
  end

  private

  def render_panel(style, revert_url: nil, editable: true, document_design: nil, save_scope_shadow_count: 0)
    component = Design::Views::ParagraphStyles::Panel.new(
      paragraph_style: style,
      panel_update_url: "/test/panel_update",
      back_url: "/test/back",
      revert_url: revert_url,
      editable: editable,
      document_design: document_design,
      save_scope_shadow_count: save_scope_shadow_count
    )
    component.define_singleton_method(:helpers) do
      obj = Object.new
      def obj.form_authenticity_token = "test-token"
      obj
    end
    component.call
  end
end
