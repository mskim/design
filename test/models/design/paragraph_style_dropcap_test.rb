require "test_helper"

class Design::ParagraphStyleDropcapTest < ActiveSupport::TestCase
  PS = Design::ParagraphStyle

  setup do
    @theme = Design::Theme.create!(name: "DC #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.find_by(doc_type: "chapter") || @ps.document_designs.create!(doc_type: "chapter")
  end

  def row(**attrs) = @dd.paragraph_styles.new(name: "zz_dc", **attrs)
  def panel_valid?(record) = record.valid?(:style_panel)

  FORM = { "lines" => "2", "chars" => "1", "align_left_edge" => "1", "scale_descenders" => "0",
           "font" => "", "color" => "", "junk" => "x" }.freeze
  CANONICAL = { "lines" => 2, "chars" => 1, "align_left_edge" => true, "scale_descenders" => false }.freeze

  test "dropcap is a mergeable style field" do
    assert_includes Design::DocumentDesign::MERGEABLE_ATTRS, "dropcap"
    assert_includes PS::STYLE_FIELDS, "dropcap"
  end

  test "normalize_dropcap: form params become the canonical hash" do
    assert_equal CANONICAL, PS.normalize_dropcap(FORM)
    assert_equal CANONICAL, PS.normalize_dropcap(FORM.to_json)
    assert_equal CANONICAL, PS.normalize_dropcap(ActionController::Parameters.new(FORM).permit!)
    assert_equal CANONICAL, PS.normalize_dropcap(FORM.transform_keys(&:to_sym))
  end

  test "normalize_dropcap keeps a stripped font and colour" do
    out = PS.normalize_dropcap("lines" => 3, "font" => " Shinmoon ", "color" => "#ff0000")
    assert_equal({ "lines" => 3, "font" => "Shinmoon", "color" => "#ff0000" }, out)
  end

  test "normalize_dropcap: enabled false is explicitly off; blank is nil" do
    assert_equal({ "enabled" => false }, PS.normalize_dropcap("enabled" => "false", "lines" => "3"))
    assert_equal({ "enabled" => false }, PS.normalize_dropcap("enabled" => false))
    assert_equal({ "enabled" => false }, PS.normalize_dropcap('{"enabled":false}'))
    [ nil, "", {}, "not json", "[1]", { "junk" => "x" } ].each { |v| assert_nil PS.normalize_dropcap(v), v.inspect }
  end

  test "normalize_dropcap leaves a non-integer count for validation to report" do
    assert_equal "2.5", PS.normalize_dropcap("lines" => "2.5")["lines"]
    assert_equal "0x2", PS.normalize_dropcap("lines" => "0x2")["lines"]
  end

  test "normalize_dropcap: enabled is cast like the flags" do
    [ 0, "0", "off", "false", false, "f" ].each do |v|
      assert_equal({ "enabled" => false }, PS.normalize_dropcap("enabled" => v), v.inspect)
    end
  end

  test "same_value? fills an enabled cap's missing keys from the default" do
    assert PS.same_value?("dropcap", { "lines" => 2 }, PS::DROPCAP_DEFAULT)
    assert PS.same_value?("dropcap", { "chars" => "1" }, '{"lines":2}')
    refute PS.same_value?("dropcap", { "lines" => 3 }, PS::DROPCAP_DEFAULT)
    refute PS.same_value?("dropcap", nil, PS::DROPCAP_DEFAULT)
    refute PS.same_value?("dropcap", { "enabled" => false }, PS::DROPCAP_DEFAULT)
    assert PS.same_value?("dropcap", { "enabled" => "off" }, { "enabled" => false })
  end

  test "style panel validation: fractional counts are not whole numbers" do
    [ { "lines" => 2.5 }, '{"lines":2.5}' ].each do |v|
      r = row(dropcap: v)
      refute panel_valid?(r), v.inspect
      assert_includes r.errors[:dropcap], I18n.t("design.style_panel.errors.dropcap_lines"), v.inspect
    end
    r = row(dropcap: { "lines" => 2, "chars" => 3.7 })
    refute panel_valid?(r)
    assert_includes r.errors[:dropcap], I18n.t("design.style_panel.errors.dropcap_chars")
  end

  test "same_value? compares dropcap by its normalized form" do
    assert PS.same_value?("dropcap", { "lines" => 2 }, '{"lines":"2"}')
    refute PS.same_value?("dropcap", { "lines" => 2 }, { "lines" => 3 })
    assert PS.same_value?("dropcap", nil, nil)
    assert PS.same_value?("dropcap", nil, {})
    refute PS.same_value?("dropcap", nil, { "enabled" => false })
    assert PS.inherits_value?("dropcap", CANONICAL, FORM)
  end

  test "assigned dropcap is normalized before validation" do
    r = row(dropcap: FORM)
    assert r.valid?
    assert_equal CANONICAL, r.dropcap
    r.save!
    assert_equal CANONICAL, r.reload.dropcap
  end

  test "style panel validation: lines 2–6 and chars 1–4" do
    [ 1, 7, "2.5", "abc" ].each do |v|
      r = row(dropcap: { "lines" => v })
      refute panel_valid?(r), v.inspect
      assert_includes r.errors[:dropcap], I18n.t("design.style_panel.errors.dropcap_lines"), v.inspect
    end
    [ 0, 5 ].each do |v|
      r = row(dropcap: { "lines" => 2, "chars" => v })
      refute panel_valid?(r), v.inspect
      assert_includes r.errors[:dropcap], I18n.t("design.style_panel.errors.dropcap_chars"), v.inspect
    end
  end

  test "style panel validation: colour and font take what the panel offers" do
    r = row(dropcap: { "lines" => 2, "color" => "blue-ish" })
    refute panel_valid?(r)
    assert_includes r.errors[:dropcap], I18n.t("design.style_panel.errors.dropcap_color")
    r = row(dropcap: { "lines" => 2, "font" => "NoSuchFont" })
    refute panel_valid?(r)
    assert_includes r.errors[:dropcap], I18n.t("design.style_panel.errors.dropcap_font")
  end

  test "style panel validation: a valid cap and an explicit off are fine" do
    assert panel_valid?(row(dropcap: FORM))
    assert panel_valid?(row(dropcap: { "lines" => 6, "chars" => 4, "font" => Design::Theme::AVAILABLE_FONTS.first,
                                       "color" => "CMYK=0,100,100,0" }))
    assert panel_valid?(row(dropcap: { "enabled" => false }))
    assert panel_valid?(row(dropcap: nil))
  end

  test "a stored dropcap font round-trips even if no longer offered" do
    r = row(dropcap: { "lines" => 2 })
    r.save!
    r.update_column(:dropcap, { "lines" => 2, "font" => "LegacyFont" })
    r.reload.dropcap = { "lines" => 3, "font" => "LegacyFont" }
    assert panel_valid?(r)
  end
end
