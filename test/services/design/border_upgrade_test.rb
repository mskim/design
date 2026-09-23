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

  # The broad case, checked against an expectation built without LegacyBorder:
  # three sizes (A: chapter row; B: chapter design without the row; C: no
  # chapter design), a name with no base row, a row with no legacy entry under
  # a bordered parent, an explicit 0, and marks whose values equal the parent.
  test "across sizes and missing chapters every design resolves to the old chain" do
    theme = Design::Theme.create!(name: "BU2 #{SecureRandom.hex(3)}", locale: "ko")
    a = theme.paper_sizes.create!(size_name: "A", width_mm: 152, height_mm: 225)
    b = theme.paper_sizes.create!(size_name: "B", width_mm: 148, height_mm: 210)
    c = theme.paper_sizes.create!(size_name: "C", width_mm: 210, height_mm: 297)
    dd = ->(ps, type) { ps.document_designs.find_by(doc_type: type) || ps.document_designs.create!(doc_type: type) }
    a_ch, a_fw, a_poem, a_epi = %w[chapter foreword poem epilogue].map { |t| dd.(a, t) }
    b_ch, b_fw = %w[chapter foreword].map { |t| dd.(b, t) }
    c_fw, c_pro = %w[foreword prologue].map { |t| dd.(c, t) }
    b.document_designs.find_by(doc_type: "chapter") || flunk
    assert_nil c.document_designs.find_by(doc_type: "chapter"), "C has no chapter design"

    old = ->(**h) { %w[border_thickness border_color border_side rounded_corners corner_radius].index_with { |f| h[f.to_sym] } }
    rows = {}
    legacy = {}
    add = lambda do |owner, key, name, values, **attrs|
      row = (owner.is_a?(Design::Theme) ? owner.base_paragraph_styles : owner.paragraph_styles).create!(name: name, **attrs)
      rows[key] = row
      legacy[row.id] = values if values
    end
    add.(theme, :base, "zz_box", old.(border_thickness: "1", border_color: "CMYK=0,0,0,100"))
    add.(a_ch, :a_ch, "zz_box", old.(rounded_corners: "1,1,0,0", corner_radius: "large"))
    add.(a_fw, :a_fw, "zz_box", nil, font_size: 12)                         # no legacy, bordered parent
    add.(a_poem, :a_poem, "zz_box", old.(border_thickness: "0"),            # explicit 0 under a border
         overridden_fields: %w[border_thickness])
    add.(a_epi, :a_epi, "zz_box", old.(border_thickness: "1", border_color: "CMYK=0,0,0,100"),
         overridden_fields: %w[border_thickness border_color font_size], font_size: 11)   # equal to parent
    add.(b_fw, :b_fw, "zz_box", old.(border_side: "1,0,1,0", rounded_corners: "0,0,1,1", corner_radius: "small"))
    add.(c_fw, :c_fw, "zz_box", old.(border_side: "0,1,0,1", border_color: "#ff0000"))
    add.(c_pro, :c_pro, "zz_box", nil, font_size: 10)
    add.(a_ch, :a_ch_only, "zz_ch_only", old.(border_thickness: "2", border_side: "1,1,1,1", corner_radius: "medium"))
    add.(a_fw, :a_fw_only, "zz_ch_only", old.(border_thickness: "0.5"))
    add.(c_fw, :c_fw_only, "zz_ch_only", old.(corner_radius: "small"))
    add.(b_ch, :b_ch_only, "zz_ch_only", old.(border_color: "#00ff00", border_thickness: "3", border_side: "0,0,0,1"))

    # The expectation, from the legacy hashes alone.
    blank = ->(v) { v.nil? || v.to_s.strip.empty? }
    flags = ->(text) { f = text.to_s.split(",").map(&:strip); f.size == 4 && f.all? { |x| %w[0 1].include?(x) } ? f.map { |x| x == "1" } : [ true ] * 4 }
    expect = lambda do |layers|
      o = layers.compact.each_with_object({}) { |h, acc| h.each { |k, v| acc[k] = v unless blank.(v) } }
      t = o["border_thickness"].to_f
      preset = { "large" => "full" }.fetch(o["corner_radius"].to_s.strip, o["corner_radius"].to_s.strip)
      preset = "none" unless %w[small medium full].include?(preset)
      sides = flags.(o["border_side"]).map { |on| t.positive? && on ? t : 0.0 }
      { thickness: sides, color: sides.map { |x| x.positive? ? o["border_color"] : nil },
        corners: flags.(o["rounded_corners"]).map { |on| on ? preset : "none" } }
    end
    chains = {}
    theme.paper_sizes.each do |ps|
      chapter = ps.document_designs.find_by(doc_type: "chapter")
      ps.document_designs.each do |d|
        %w[zz_box zz_ch_only].each do |name|
          own = d.paragraph_styles.find_by(name: name)
          ch = chapter && d != chapter ? chapter.paragraph_styles.find_by(name: name) : nil
          base = theme.base_paragraph_styles.find_by(name: name)
          next unless own || ch || base
          chains[[ d.id, name ]] = expect.([ base, ch, own ].map { |r| r && legacy[r.id] })
        end
      end
    end
    base_expected = expect.([ legacy[rows[:base].id] ])

    Design::BorderUpgrade.rewrite!(theme, legacy)

    got = lambda do |r|
      { thickness: PS::BORDER_THICKNESS_FIELDS.map { |f| r[f].to_f },
        color: PS::BORDER_COLOR_FIELDS.map { |f| r[f] }, corners: PS::CORNER_FIELDS.map { |f| r[f] || "none" } }
    end
    check = lambda do |label, expected, actual|
      assert_equal expected[:thickness], actual[:thickness], "#{label} thickness"
      assert_equal expected[:corners], actual[:corners], "#{label} corners"
      expected[:thickness].each_with_index do |t, i|
        next unless t.positive?
        msg = "#{label} colour #{Design::LegacyBorder::SIDES[i]}"
        expected[:color][i].nil? ? assert_nil(actual[:color][i], msg) : assert_equal(expected[:color][i], actual[:color][i], msg)
      end
    end
    check.("base zz_box", base_expected, got.(theme.base_paragraph_styles.find_by(name: "zz_box")))
    assert_equal 15, chains.size, "A: 4 designs × 2 names; B: 2 × 2; C: 2 zz_box + the foreword's zz_ch_only"
    chains.each do |(dd_id, name), expected|
      d = Design::DocumentDesign.find(dd_id)
      merged = d.merged_paragraph_styles.index_by(&:name).fetch(name)
      check.("#{d.paper_size.size_name} #{d.doc_type} #{name}", expected, got.(merged))
    end
    assert_equal [ 1.0, 0, 1.0, 0 ], chains[[ b_fw.id, "zz_box" ]][:thickness], "sanity: B foreword's own sides"
    assert_equal [ 0, 1.0, 0, 1.0 ], chains[[ c_fw.id, "zz_box" ]][:thickness], "sanity: C foreword under the base only"

    poem = a_poem.paragraph_styles.find_by(name: "zz_box")
    assert_equal PS::BORDER_THICKNESS_FIELDS.sort, (poem.overridden_fields & PS::BORDER_FIELDS).sort,
                 "the explicit 0 stays pinned on all four sides"
    refute_includes poem.overridden_fields, "border_thickness"
    epi = a_epi.paragraph_styles.find_by(name: "zz_box")
    assert epi, "kept for its font_size"
    assert_empty epi.overridden_fields & (PS::BORDER_FIELDS + Design::LegacyBorder::OLD_FIELDS),
                 "marks equal to the parent are cleared with their values"
    assert_includes epi.overridden_fields, "font_size"
    PS::BORDER_FIELDS.each { |f| assert_nil epi[f], f }
  end

  test "legacy_values reads the old columns through a connection" do
    conn = Object.new
    def conn.select_rows(_sql) = [ [ 7, "1", "#000000", "1,1,1,1", nil, "small" ] ]
    assert_equal({ 7 => { "border_thickness" => "1", "border_color" => "#000000", "border_side" => "1,1,1,1",
                          "rounded_corners" => nil, "corner_radius" => "small" } },
                 Design::BorderUpgrade.legacy_values(conn))
  end
end
