require "test_helper"

# Drop cap plan, Task 7: the 드롭 캡 section — only on the body style; one
# box whose value[...] controls save the whole dropcap hash as one field.
class Design::DropcapSectionTest < ActiveSupport::TestCase
  PS = Design::ParagraphStyle
  Content = Design::Views::ParagraphStyles::StylePanelContent

  setup do
    @theme = Design::Theme.create!(name: "DC #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @chapter = design_for("chapter")
    @foreword = design_for("foreword")
    @base = @theme.base_paragraph_styles.create!(name: "body", font: "Base Font", font_size: 10)
    @theme.base_paragraph_styles.create!(name: "h2", font: "Base Font", font_size: 14)
  end

  def design_for(t) = @ps.document_designs.find_by(doc_type: t) || @ps.document_designs.create!(doc_type: t)
  def content(name = "body", dd = @foreword, **opts) = Nokogiri::HTML.fragment(Content.new(document_design: dd, style_name: name, **opts).call)
  def box(doc) = doc.at_css("[data-group='dropcap']")
  def ctl(doc, key) = box(doc).at_css("[name='value[#{key}]']:not([type=hidden])") || box(doc).at_css("[name='value[#{key}]']")

  test "the body panel has a 드롭 캡 section with every control" do
    doc = content
    assert doc.at_css("details[data-section='dropcap']")
    b = box(doc)
    assert b, "the dropcap box"
    assert_equal "dropcap", b["data-hash-field"]
    assert_equal "checkbox", ctl(doc, "enabled")["type"]
    { "lines" => [ 2, 6 ], "chars" => [ 1, 4 ] }.each do |k, (min, max)|
      input = ctl(doc, k)
      assert_equal "text", input["type"], k
      scrub = input.ancestors("[data-controller='design--scrub-input']").first
      assert_equal min.to_s, scrub["data-design--scrub-input-min-value"], k
      assert_equal max.to_s, scrub["data-design--scrub-input-max-value"], k
    end
    font = ctl(doc, "font")
    assert_equal "select", font.name
    blank = font.at_css("option[value='']")
    assert_equal I18n.t("design.dropcap.same_as_body"), blank.text
    Design::Theme::AVAILABLE_FONTS.each { |f| assert font.at_css("option[value='#{f}']"), f }
    assert b.at_css("[data-controller~='design--color-row'] input[type=hidden][name='value[color]']")
    %w[enabled align_left_edge scale_descenders].each do |k|
      hidden, check = b.css("[name='value[#{k}]']").to_a
      assert_equal [ "hidden", "0" ], [ hidden["type"], hidden["value"] ], "#{k}: a hidden 0 comes first"
      assert_equal [ "checkbox", "1" ], [ check["type"], check["value"] ], k
    end
  end

  test "an h2 panel has no dropcap section" do
    doc = content("h2")
    assert_nil doc.at_css("details[data-section='dropcap']")
    assert_nil doc.at_css("[data-group='dropcap']")
    assert_nil doc.at_css("[name^='value[']")
  end

  test "no cap anywhere: off, the parts show the defaults and are disabled, inherited state" do
    doc = content
    refute ctl(doc, "enabled").key?("checked")
    assert_equal "2", ctl(doc, "lines")["value"]
    assert_equal "1", ctl(doc, "chars")["value"]
    assert ctl(doc, "align_left_edge").key?("checked")
    refute ctl(doc, "scale_descenders").key?("checked")
    assert ctl(doc, "lines").key?("disabled"), "parts are off with the cap"
    refute ctl(doc, "enabled").key?("disabled")
    assert_equal "false", box(doc)["data-parent-on"]
    row = doc.at_css("[data-style-field='dropcap']")
    assert_equal "inherited", row["data-state"]
  end

  test "a stored cap fills the inputs and shows the changed dot and an active ×" do
    @foreword.set_style_field!("body", "dropcap", { "lines" => 3, "chars" => 2, "font" => Design::Theme::AVAILABLE_FONTS.first,
                                                    "color" => "#ff0000", "align_left_edge" => false, "scale_descenders" => true })
    @foreword.reload
    doc = content
    assert ctl(doc, "enabled").key?("checked")
    assert_equal "3", ctl(doc, "lines")["value"]
    assert_equal "2", ctl(doc, "chars")["value"]
    refute ctl(doc, "lines").key?("disabled")
    assert_equal Design::Theme::AVAILABLE_FONTS.first, ctl(doc, "font").at_css("option[selected]")["value"]
    assert_equal "#ff0000", box(doc).at_css("input[type=hidden][name='value[color]']")["value"]
    refute ctl(doc, "align_left_edge").key?("checked")
    assert ctl(doc, "scale_descenders").key?("checked")
    row = doc.at_css("[data-style-field='dropcap']")
    assert_equal "changed", row["data-state"]
    assert_includes row.at_css("[data-dot]")["class"], "bg-blue-600"
    x = row.at_css("button[data-action='design--style-autosave#revert'][data-field='dropcap']")
    refute x.key?("disabled")
    assert doc.at_css("details[data-section='dropcap'][open]"), "a changed section opens"
  end

  test "a cap inherited from the theme base shows on, its values, inherited state and parent-on" do
    @base.update!(dropcap: { "lines" => 4, "chars" => 1 })
    doc = content
    assert ctl(doc, "enabled").key?("checked")
    assert_equal "4", ctl(doc, "lines")["value"]
    assert_equal "true", box(doc)["data-parent-on"]
    assert_equal "inherited", doc.at_css("[data-style-field='dropcap']")["data-state"]
  end

  test "an explicit off over the base cap: unchecked, parent-on, changed" do
    @base.update!(dropcap: PS::DROPCAP_DEFAULT)
    @foreword.set_style_field!("body", "dropcap", PS::DROPCAP_OFF)
    @foreword.reload
    doc = content
    refute ctl(doc, "enabled").key?("checked")
    assert_equal "true", box(doc)["data-parent-on"]
    assert_equal "changed", doc.at_css("[data-style-field='dropcap']")["data-state"]
  end

  test "after a 422 the attempted JSON value refills the inputs and the message shows" do
    doc = content(field_errors: { "dropcap" => [ "줄 수는 2–6이어야 합니다" ] },
                  attempted: { "dropcap" => { "lines" => 9, "chars" => 3 }.to_json })
    assert ctl(doc, "enabled").key?("checked")
    assert_equal "9", ctl(doc, "lines")["value"]
    assert_equal "3", ctl(doc, "chars")["value"]
    assert_equal "줄 수는 2–6이어야 합니다", doc.at_css("[data-field-error='dropcap']").text
  end

  test "read-only: every control is disabled" do
    doc = content(editable: false)
    box(doc).css("input[name], select, [data-design--color-row-target=trigger]").each { |el| assert el.key?("disabled"), el.to_html[0, 80] }
  end
end
