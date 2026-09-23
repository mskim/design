require "test_helper"

# D5: rows rewritten from the old five fields resolve exactly as before
# (except large → full), overrides stay on the rows that had them, and they
# stay pushable.
class Design::BorderUpgradeTest < ActiveSupport::TestCase
  PS = Design::ParagraphStyle

  setup do
    @theme = Design::Theme.create!(name: "BU #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @chapter = design("chapter")
    @foreword = design("foreword")
    @base = @theme.base_paragraph_styles.create!(name: "zz_box")
    @ch_row = @chapter.paragraph_styles.create!(name: "zz_box")
    @fw_row = @foreword.paragraph_styles.create!(name: "zz_box", overridden_fields: %w[border_side font_size],
                                                 font_size: 11)
    @legacy = {
      @base.id => { "border_thickness" => "1", "border_color" => "CMYK=0,0,0,100", "border_side" => nil,
                    "rounded_corners" => nil, "corner_radius" => nil },
      @ch_row.id => { "border_thickness" => nil, "border_color" => nil, "border_side" => nil,
                      "rounded_corners" => "1,1,0,0", "corner_radius" => "large" },
      @fw_row.id => { "border_thickness" => nil, "border_color" => nil, "border_side" => "1,0,1,0",
                      "rounded_corners" => nil, "corner_radius" => nil }
    }
  end

  def design(doc_type) = @ps.document_designs.find_by(doc_type: doc_type) || @ps.document_designs.create!(doc_type: doc_type)

  def resolved(dd, name = "zz_box")
    layers = [ @theme.base_paragraph_styles.find_by(name: name) ]
    layers << @chapter.paragraph_styles.find_by(name: name) unless dd == @chapter || dd.nil?
    layers << dd.paragraph_styles.find_by(name: name) if dd
    PS::BORDER_FIELDS.index_with { |f| layers.compact.reverse.map { |r| r[f] }.find { |v| !v.nil? } }
  end

  def number(v) = v.nil? ? nil : v.to_f

  test "every row resolves to the converted old chain" do
    Design::BorderUpgrade.rewrite!(@theme, @legacy)
    base_expected = Design::LegacyBorder.convert(@legacy[@base.id])
    chapter_expected = Design::LegacyBorder.convert(Design::LegacyBorder.overlay([ @legacy[@base.id], @legacy[@ch_row.id] ]))
    fw_expected = Design::LegacyBorder.convert(Design::LegacyBorder.overlay(@legacy.values_at(@base.id, @ch_row.id, @fw_row.id)))
    { nil => base_expected, @chapter => chapter_expected, @foreword => fw_expected }.each do |dd, expected|
      got = resolved(dd)
      PS::BORDER_THICKNESS_FIELDS.each { |f| assert_equal number(expected[f]), number(got[f]), "#{dd&.doc_type || 'base'} #{f}" }
      (PS::BORDER_COLOR_FIELDS + PS::CORNER_FIELDS).each { |f| assert_equal expected[f], got[f], "#{dd&.doc_type || 'base'} #{f}" }
    end
    assert_equal %w[full full none none], PS::CORNER_FIELDS.map { |f| resolved(@foreword)[f] }, "large → full, inherited"
    assert_equal [ 1.0, 0.0, 1.0, 0.0 ], PS::BORDER_THICKNESS_FIELDS.map { |f| number(resolved(@foreword)[f]) }
  end

  test "overrides stay on the rows that had them" do
    Design::BorderUpgrade.rewrite!(@theme, @legacy)
    fw = @foreword.paragraph_styles.find_by(name: "zz_box")
    assert_equal 0, fw.border_right_thickness.to_i, "the foreword's own sides are stored"
    assert_nil fw.corner_top_left, "the corners were the chapter's: inherited here"
    ch = @chapter.paragraph_styles.find_by(name: "zz_box")
    assert_equal "full", ch.corner_top_left
    assert_nil ch.border_top_thickness, "the thickness was the base's: inherited here"
  end

  test "overridden_fields: the old names give way to the new fields still set" do
    Design::BorderUpgrade.rewrite!(@theme, @legacy)
    fw = @foreword.paragraph_styles.find_by(name: "zz_box")
    refute_includes fw.overridden_fields, "border_side"
    assert_includes fw.overridden_fields, "font_size", "unrelated marks stay"
    assert_includes fw.overridden_fields, "border_right_thickness"
    PS::BORDER_FIELDS.each { |f| refute_includes fw.overridden_fields, f if fw[f].nil? }
    ch = @chapter.paragraph_styles.find_by(name: "zz_box")
    assert_empty ch.overridden_fields & PS::BORDER_FIELDS, "the chapter had no marks, so none are added"
  end

  test "a row without legacy values (e.g. generator-made) inherits cleanly" do
    extra = @foreword.paragraph_styles.create!(name: "zz_other", font_size: 12)
    Design::BorderUpgrade.rewrite!(@theme, @legacy)
    extra.reload
    PS::BORDER_FIELDS.each { |f| assert_nil extra[f], f }
  end

  test "legacy_values reads the old columns through a connection" do
    conn = Object.new
    def conn.select_rows(_sql) = [ [ 7, "1", "#000000", "1,1,1,1", nil, "small" ] ]
    assert_equal({ 7 => { "border_thickness" => "1", "border_color" => "#000000", "border_side" => "1,1,1,1",
                          "rounded_corners" => nil, "corner_radius" => "small" } },
                 Design::BorderUpgrade.legacy_values(conn))
  end
end
