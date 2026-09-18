require "test_helper"

# D3: the Page section validates only in the :page_section context and only
# the fields named by `page_field` (a transient list the endpoint sets).
class Design::PageSectionValidationTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "PSV #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225) # 22/22/18/28, binding 3
    @chapter = @ps.document_designs.create!(doc_type: "chapter")
    @poem = @ps.document_designs.create!(doc_type: "poem")
  end

  def err(key, **opts) = I18n.t("design.page_section.errors.#{key}", **opts)

  def set_margin(values)
    @ps.assign_attributes(values)
    @ps.page_field = values.keys.map(&:to_s)
    @ps.valid?(:page_section)
  end

  def set_design(dd = @chapter, values)
    dd.assign_attributes(values)
    dd.page_field = values.keys.map(&:to_s)
    dd.valid?(:page_section)
  end

  test "a margin is a plain decimal ≥ 0: no exponent, no unit, not blank" do
    { "abc" => :not_a_number, "1e1" => :not_a_number, "12mm" => :not_a_number, "-1" => :negative, "" => :required }.each do |v, key|
      refute set_margin(top_margin_mm: v), v.inspect
      assert_equal [ err(key) ], @ps.errors[:top_margin_mm], v.inspect
      @ps.reload
    end
    [ "18", "18.5", ".5", " 18 ", "0" ].each { |v| assert set_margin(top_margin_mm: v), v.inspect; @ps.reload }
  end

  test "left + right + binding must leave 20 mm of width; top + bottom 20 mm of height" do
    refute set_margin(left_margin_mm: "120")           # 152 - 120 - 22 - 3 = 7
    assert_equal [ err(:too_narrow, min: 20) ], @ps.errors[:left_margin_mm]
    @ps.reload
    refute set_margin(binding_margin_mm: "108")        # 152 - 22 - 22 - 108 = 0
    assert_equal [ err(:too_narrow, min: 20) ], @ps.errors[:binding_margin_mm]
    @ps.reload
    refute set_margin(top_margin_mm: "180")            # 225 - 180 - 28 = 17
    assert_equal [ err(:too_short, min: 20) ], @ps.errors[:top_margin_mm]
    @ps.reload
    assert set_margin(left_margin_mm: "100")           # 27 mm left
  end

  test "only the fields being set are checked, and only a worse width or height is rejected" do
    @ps.update_columns(left_margin_mm: 125)            # stored width 152 - 125 - 22 - 3 = 2 mm
    assert set_margin(top_margin_mm: "20"), "a stored bad width never blocks a top save"
    @ps.reload
    assert set_margin(right_margin_mm: "10"), "14 mm: better than 2 mm, accepted though still under 20"
    @ps.reload
    refute set_margin(right_margin_mm: "30"), "-6 mm: worse than the stored 2 mm"
    assert_equal [ err(:too_narrow, min: 20) ], @ps.errors[:right_margin_mm]
    @ps.reload
    assert set_margin(left_margin_mm: "30"), "a full fix is accepted"
    @ps.reload
    @ps.update_columns(top_margin_mm: 190)             # stored height 225 - 190 - 28 = 7 mm
    assert set_margin(top_margin_mm: "185"), "12 mm: better"
    @ps.reload
    refute set_margin(bottom_margin_mm: "40"), "-5 mm: worse"
  end

  test "the linked pair is validated together" do
    refute set_margin(left_margin_mm: "70", right_margin_mm: "70")
    assert_equal [ err(:too_narrow, min: 20) ], @ps.errors[:left_margin_mm]
    assert_equal [ err(:too_narrow, min: 20) ], @ps.errors[:right_margin_mm]
  end

  # Poem never gets the binding, so its text width is width - left - right
  # (108 mm = 306.1 pt today); chapter's is the print width (105 mm = 297.6 pt).
  test "a width change is checked against every doc type's columns on the size, naming the doc type" do
    @poem.update_columns(column_count: 3, gutter: 145) # 290 pt of gutters: fits in 306.1 pt
    refute set_margin(left_margin_mm: "30")            # poem: 100 mm = 283.5 pt
    assert_equal [ err(:columns_elsewhere, doc_types: I18n.t("design.doc_types.poem")) ], @ps.errors[:left_margin_mm]
    @ps.reload
    assert set_margin(left_margin_mm: "25")            # poem: 105 mm = 297.6 pt
  end

  test "only newly broken doc types block a width save; one already broken never does" do
    @poem.update_columns(column_count: 3, gutter: 145)
    @ps.update_columns(left_margin_mm: 40)             # poem: 90 mm = 255.1 pt < 290 pt — already broken
    assert set_margin(left_margin_mm: "35"), "improving (poem 95 mm), not a full fix: accepted"
    @ps.reload
    assert set_margin(right_margin_mm: "30"), "poem was broken at the stored width: not newly broken"
    @ps.reload
    @chapter.update_columns(column_count: 2, gutter: 200) # chapter print width at left 40: 87 mm = 246.6 pt, fits
    refute set_margin(left_margin_mm: "60")            # chapter: 67 mm = 189.9 pt — newly broken; poem still broken
    assert_equal [ err(:columns_elsewhere, doc_types: I18n.t("design.doc_types.chapter")) ], @ps.errors[:left_margin_mm],
                 "only the newly broken doc type is named"
  end

  # Chapter's text width counts the binding; poem's never does.
  test "a binding save that breaks chapter's columns but not poem's is rejected, naming chapter only" do
    [ @chapter, @poem ].each { |dd| dd.update_columns(column_count: 2, gutter: 280) }
    refute set_margin(binding_margin_mm: "10")         # chapter: 152 - 44 - 10 = 98 mm = 277.8 pt < 280; poem: 306.1 pt
    assert_equal [ err(:columns_elsewhere, doc_types: I18n.t("design.doc_types.chapter")) ], @ps.errors[:binding_margin_mm]
  end

  test "the linked pair reports columns_elsewhere on both fields" do
    @chapter.update_columns(column_count: 2, gutter: 280)
    refute set_margin(left_margin_mm: "26", right_margin_mm: "26") # chapter: 152 - 52 - 3 = 97 mm = 275 pt < 280
    expected = [ err(:columns_elsewhere, doc_types: I18n.t("design.doc_types.chapter")) ]
    assert_equal expected, @ps.errors[:left_margin_mm]
    assert_equal expected, @ps.errors[:right_margin_mm]
  end

  test "a raw value that is neither String nor Numeric is not a number, never a NoMethodError" do
    [ true, [ 1 ], { "a" => 1 } ].each do |v|
      refute set_margin(top_margin_mm: v), v.inspect
      assert_equal [ err(:not_a_number) ], @ps.errors[:top_margin_mm], v.inspect
      @ps.reload
      refute set_design(gutter: v), v.inspect
      assert_equal [ err(:not_a_number) ], @chapter.errors[:gutter], v.inspect
      @chapter.reload
      refute set_design(column_count: v), v.inspect
      assert_equal [ err(:not_an_integer) ], @chapter.errors[:column_count], "#{v.inspect}: integer fields say so, as for \"abc\""
      @chapter.reload
    end
  end

  # Chapter's column width here is the print width, 105 mm = 297.6 pt.
  test "columns: only a save that makes things worse is rejected" do
    @chapter.update_columns(column_count: 3, gutter: 160) # 320 pt of gutters: already broken
    assert set_design(gutter: "155"), "310 pt: better, though still broken"
    @chapter.reload
    refute set_design(gutter: "165"), "330 pt: worse"
    assert_equal [ err(:no_column_width) ], @chapter.errors[:gutter]
    @chapter.reload
    assert set_design(column_count: "2"), "160 pt: fewer columns, fixed"
    @chapter.reload
    refute set_design(column_count: "4"), "480 pt: more columns, worse"
    assert_equal [ err(:no_column_width) ], @chapter.errors[:column_count]
    @chapter.reload
    @chapter.update_columns(column_count: 3, gutter: 12) # fits
    refute set_design(gutter: "150"), "300 pt: a fitting layout newly broken"
    assert_equal [ err(:no_column_width) ], @chapter.errors[:gutter]
  end

  test "nothing is checked outside the :page_section context, or without page_field" do
    @ps.top_margin_mm = "abc"
    @ps.page_field = %w[top_margin_mm]
    assert @ps.valid?, "importers, the paper size form and generators never use the context"
    @ps.page_field = nil
    assert @ps.valid?(:page_section)
  end

  test "column count: a whole number 1–6, required" do
    { "0" => :out_of_range, "7" => :out_of_range, "2.5" => :not_an_integer, "abc" => :not_an_integer, "" => :required }.each do |v, key|
      refute set_design(column_count: v), v.inspect
      expected = key == :out_of_range ? err(key, min: 1, max: 6) : err(key)
      assert_equal [ expected ], @chapter.errors[:column_count], v.inspect
      @chapter.reload
    end
    assert set_design(column_count: "3")
  end

  test "gutter: a decimal ≥ 0, required; the columns must keep a positive width" do
    { "-1" => :negative, "" => :required, "1e2" => :not_a_number }.each do |v, key|
      refute set_design(gutter: v), v.inspect
      assert_equal [ err(key) ], @chapter.errors[:gutter], v.inspect
      @chapter.reload
    end
    @chapter.update_columns(column_count: 3)
    refute set_design(gutter: "150")                   # 300 pt ≥ (152-22-22-3) mm = 297.6 pt
    assert_equal [ err(:no_column_width) ], @chapter.errors[:gutter]
    @chapter.reload
    assert set_design(gutter: "12")
  end

  test "body line count: a whole number 1–100, above the design's heading lines" do
    refute set_design(body_line_count: "101")
    assert_equal [ err(:out_of_range, min: 1, max: 100) ], @chapter.errors[:body_line_count]
    @chapter.reload
    refute set_design(body_line_count: "6")            # heading_height_in_lines defaults to 6
    assert_equal [ err(:not_above_heading, lines: 6) ], @chapter.errors[:body_line_count]
    @chapter.reload
    refute set_design(body_line_count: "abc")
    assert_equal [ err(:not_an_integer) ], @chapter.errors[:body_line_count]
    @chapter.reload
    assert set_design(body_line_count: "7")
  end

  test "columns_fit? uses the print width only where binding applies; margin_changed?" do
    assert @chapter.columns_fit?
    [ @chapter, @poem ].each { |dd| dd.column_count = 2; dd.gutter = 300 }
    refute @chapter.columns_fit?, "chapter: print width 105 mm = 297.6 pt < 300 pt"
    assert @poem.columns_fit?, "poem: no binding, 108 mm = 306.1 pt > 300 pt"
    ps = @theme.paper_sizes.create!(size_name: "X", width_mm: 152, height_mm: 225, left_margin_mm: 22, top_margin_mm: 30)
    assert ps.overridden?(:left_margin_mm), "an explicit creation value is marked"
    refute ps.margin_changed?("left_margin_mm"), "…but equals the rule: no dot"
    assert ps.margin_changed?("top_margin_mm")
    refute ps.margin_changed?("bottom_margin_mm"), "not marked"
  end

  test "margin_problems reports stored margins that leave under 20 mm" do
    assert_empty @ps.margin_problems
    @ps.update_columns(left_margin_mm: 70, right_margin_mm: 70, top_margin_mm: 190)
    assert_equal [ err(:too_narrow, min: 20), err(:too_short, min: 20) ], @ps.margin_problems
  end
end
