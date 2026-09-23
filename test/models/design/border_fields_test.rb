require "test_helper"
require "sqlite3"

# D5: a thickness and a colour per side, a corner preset per corner, each an
# ordinary inheritable style field.
class Design::BorderFieldsTest < ActiveSupport::TestCase
  PS = Design::ParagraphStyle
  OLD = %w[border_thickness border_color border_side rounded_corners corner_radius].freeze

  setup do
    @theme = Design::Theme.create!(name: "BF #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.find_by(doc_type: "foreword") || @ps.document_designs.create!(doc_type: "foreword")
  end

  test "the twelve are style fields, in both lists, and the old five are gone" do
    assert_equal 12, PS::BORDER_FIELDS.size
    assert_equal PS::BORDER_FIELDS.sort, Design::LegacyBorder::NEW_FIELDS.sort
    PS::BORDER_FIELDS.each do |f|
      assert_includes PS::STYLE_FIELDS, f
      assert_includes Design::DocumentDesign::MERGEABLE_ATTRS, f
      assert PS.column_names.include?(f), "#{f} column"
    end
    OLD.each do |f|
      refute_includes PS::STYLE_FIELDS, f
      refute PS.column_names.include?(f), "#{f} column should be dropped"
    end
    refute PS.const_defined?(:CORNER_RADII)
    refute PS.const_defined?(:FLAG_FIELDS)
  end

  test "link groups name exactly four fields each, and link_group_for finds a group in any order" do
    assert_equal %w[border_color border_thickness corners], PS::LINK_GROUPS.keys.sort
    assert_equal "corners", PS.link_group_for(PS::CORNER_FIELDS.reverse)
    assert_equal "border_thickness", PS.link_group_for(PS::BORDER_THICKNESS_FIELDS.map(&:to_sym))
    assert_nil PS.link_group_for(PS::CORNER_FIELDS.first(3))
    assert_nil PS.link_group_for(PS::CORNER_FIELDS + [ "font" ])
    assert_nil PS.link_group_for(nil)
  end

  test "the style panel validates each new field" do
    row = @dd.paragraph_styles.build(name: "zz_box")
    row.assign_attributes("border_top_thickness" => "-1", "border_right_thickness" => "abc",
                          "border_top_color" => "nope", "corner_top_left" => "large", "corner_top_right" => "full")
    refute row.valid?(:style_panel)
    assert row.errors["border_top_thickness"].any?
    assert row.errors["border_right_thickness"].any?
    assert row.errors["border_top_color"].any?
    assert row.errors["corner_top_left"].any?, "large is not a D5 preset"
    assert_empty row.errors["corner_top_right"]
  end

  test "the exported theme .db carries the twelve and not the five" do
    @theme.base_paragraph_styles.create!(name: "zz_box", border_top_thickness: 1.5, border_top_color: "#ff0000",
                                         corner_top_left: "full")
    path = Design::ThemeDbExportService.new(@theme).export!
    db = SQLite3::Database.new(path)
    db.results_as_hash = true
    cols = db.execute("PRAGMA table_info(paragraph_styles)").map { _1["name"] }
    PS::BORDER_FIELDS.each { |f| assert_includes cols, f }
    OLD.each { |f| refute_includes cols, f }
    row = db.get_first_row("SELECT * FROM paragraph_styles WHERE name = 'zz_box'")
    assert_equal 1.5, row["border_top_thickness"]
    assert_equal "#ff0000", row["border_top_color"]
    assert_equal "full", row["corner_top_left"]
  ensure
    db&.close
    File.delete(path) if path && File.exist?(path)
  end

  test "the preview hands the twelve keys to the engine as numbers and strings" do
    style = PS.new(name: "b", border_bottom_thickness: BigDecimal("2"), border_bottom_color: "CMYK=0,0,0,50",
                   corner_top_right: "small")
    # new, not allocate: build_style_attrs falls back to the theme's body font
    # and the design's line height (the initializer only stores them).
    attrs = Design::PreviewService.new(@dd).send(:build_style_attrs, style)
    assert_equal 2.0, attrs[:border_bottom_thickness]
    assert_kind_of Float, attrs[:border_bottom_thickness]
    assert_equal "CMYK=0,0,0,50", attrs[:border_bottom_color]
    assert_equal "small", attrs[:corner_top_right]
    OLD.each { |f| refute attrs.key?(f.to_sym), f }
  end
end
