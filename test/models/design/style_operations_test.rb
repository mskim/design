require "test_helper"

class Design::StyleOperationsTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "Ops #{SecureRandom.hex(3)}", locale: "ko")
    @ps1 = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @ps2 = @theme.paper_sizes.create!(size_name: "국판", width_mm: 148, height_mm: 210)
    @chapters  = [ @ps1, @ps2 ].map { |ps| design_for(ps, "chapter") }
    @forewords = [ @ps1, @ps2 ].map { |ps| design_for(ps, "foreword") }
    @chapter, @foreword = @chapters.first, @forewords.first
    @base = @theme.base_paragraph_styles.create!(name: "zz_body", font: "Base Font", font_size: 10,
                                                 text_align: "left")
  end

  test "set_style_field! writes the field on every size of the doc type and marks it" do
    @foreword.set_style_field!("zz_body", "font_size", 11)

    @forewords.each do |dd|
      row = row_of(dd, "zz_body")
      assert row, "foreword on #{dd.paper_size.size_name} should have a row"
      assert_equal 11, row.font_size.to_i
      assert_includes row.overridden_fields, "font_size"
      assert_nil row.font, "only the set field is stored"
    end
    @chapters.each { |dd| assert_nil row_of(dd, "zz_body"), "chapter must stay untouched" }
  end

  test "setting a value equal to the parent clears the field and deletes the empty row" do
    @foreword.set_style_field!("zz_body", "font_size", 11)
    @foreword.set_style_field!("zz_body", "font_size", "10.0")

    @forewords.each { |dd| assert_nil row_of(dd, "zz_body") }
  end

  test "setting a value equal to the parent keeps other fields" do
    @foreword.set_style_field!("zz_body", "font_size", 11)
    @foreword.set_style_field!("zz_body", "text_align", "center")
    @foreword.set_style_field!("zz_body", "font_size", 10)

    @forewords.each do |dd|
      row = row_of(dd, "zz_body")
      assert_nil row.font_size
      assert_equal "center", row.text_align
      assert_equal [ "text_align" ], row.overridden_fields
    end
  end

  test "set_style_field! with a blank string or nil clears the field and never marks it" do
    @foreword.set_style_field!("zz_body", "font_size", 11)
    @foreword.set_style_field!("zz_body", "text_align", "center")

    @foreword.set_style_field!("zz_body", "font_size", "")
    @forewords.each do |dd|
      row = row_of(dd, "zz_body")
      assert_nil row.font_size
      refute_includes row.overridden_fields, "font_size"
    end

    @foreword.set_style_field!("zz_body", "text_align", nil)
    @forewords.each { |dd| assert_nil row_of(dd, "zz_body") }

    @foreword.set_style_field!("zz_body", "font", "   ")
    @forewords.each { |dd| assert_nil row_of(dd, "zz_body"), "blank must not create a row" }
  end

  test "set_style_field! rejects non-style fields" do
    assert_raises(ArgumentError) { @foreword.set_style_field!("zz_body", "name", "x") }
    assert_raises(ArgumentError) { @foreword.revert_style_field!("zz_body", "korean_name") }
  end

  test "clear_style_fields! rejects non-style fields" do
    @foreword.paragraph_styles.create!(name: "zz_body", korean_name: "본문", font_size: 12)
    assert_raises(ArgumentError) { @foreword.send(:clear_style_fields!, "zz_body", %w[font_size korean_name]) }
    assert_equal 12, row_of(@foreword, "zz_body").font_size.to_i, "nothing cleared"
  end

  test "revert_style_field! clears on all sizes and unmarks" do
    @foreword.set_style_field!("zz_body", "font_size", 11)
    @foreword.set_style_field!("zz_body", "text_align", "center")

    @forewords.last.revert_style_field!("zz_body", "font_size")

    @forewords.each do |dd|
      row = row_of(dd, "zz_body")
      assert_nil row.font_size
      refute_includes row.overridden_fields, "font_size"
      assert_equal "center", row.text_align
    end
  end

  test "revert_style! deletes the rows on all sizes" do
    @foreword.set_style_field!("zz_body", "font_size", 11)
    @foreword.revert_style!("zz_body")

    @forewords.each { |dd| assert_nil row_of(dd, "zz_body") }
  end

  test "a parentless style is never auto-deleted by revert-field" do
    @forewords.each { |dd| dd.paragraph_styles.create!(name: "zz_orphan", font_size: 9) }

    @foreword.revert_style_field!("zz_orphan", "font_size")
    @foreword.revert_style!("zz_orphan")

    @forewords.each do |dd|
      row = row_of(dd, "zz_orphan")
      assert row, "parentless row must survive"
      assert_nil row.font_size
    end
  end

  test "create_style! adds an empty row on every size of the doc type, kept though parentless" do
    @foreword.create_style!("zz_new", korean_name: "새")

    @forewords.each do |dd|
      row = row_of(dd, "zz_new")
      assert row, "foreword on #{dd.paper_size.size_name} should have a row"
      assert_equal "새", row.korean_name
      assert Design::ParagraphStyle::STYLE_FIELDS.all? { |f| row[f].nil? }, "no field stored"
    end
    @chapters.each { |dd| assert_nil row_of(dd, "zz_new"), "chapter must stay untouched" }

    @foreword.revert_style!("zz_new")
    @forewords.each { |dd| assert row_of(dd, "zz_new"), "parentless row survives revert_style!" }
  end

  test "push_style! from chapter writes user fields to the theme base and clears them on every chapter" do
    @chapter.set_style_field!("zz_body", "font_size", 11)
    # generator-only value: stored but not user-marked
    @chapters.each { |dd| row_of(dd, "zz_body").update!(text_align: "center") }

    @chapter.push_style!("zz_body")

    @base.reload
    assert_equal 11, @base.font_size.to_i
    assert_equal "left", @base.text_align, "generator-only values are not pushed"
    @chapters.each do |dd|
      row = row_of(dd, "zz_body")
      assert_nil row.font_size
      refute_includes row.overridden_fields, "font_size"
      assert_equal "center", row.text_align
    end
  end

  test "push_style! from chapter creates the theme base when missing" do
    @chapters.each { |dd| dd.paragraph_styles.create!(name: "zz_new", font: "Ch Font", overridden_fields: [ "font" ]) }

    @chapter.push_style!("zz_new")

    base = @theme.base_paragraph_styles.find_by(name: "zz_new")
    assert base
    assert_equal "Ch Font", base.font
    @chapters.each { |dd| assert_nil row_of(dd, "zz_new"), "the emptied chapter row now has a parent → deleted" }
  end

  test "push_style! from a doc type writes to chapter on all sizes; a sibling's own value survives" do
    prologue = design_for(@ps1, "prologue")
    prologue.paragraph_styles.create!(name: "zz_body", font_size: 13)
    @foreword.set_style_field!("zz_body", "font_size", 12)

    assert_equal({ "font_size" => 1 }, @foreword.push_preview("zz_body"))

    @foreword.push_style!("zz_body")

    @chapters.each do |dd|
      row = row_of(dd, "zz_body")
      assert_equal 12, row.font_size.to_i
      assert_includes row.overridden_fields, "font_size"
    end
    @forewords.each { |dd| assert_nil row_of(dd, "zz_body") }
    assert_equal 13, row_of(prologue, "zz_body").font_size.to_i
  end

  test "push_preview counts no siblings when none override the field" do
    @foreword.set_style_field!("zz_body", "font_size", 12)
    assert_equal({ "font_size" => 0 }, @foreword.push_preview("zz_body"))
  end

  test "style_state reports changed and user fields and parent values" do
    @chapter.set_style_field!("zz_body", "font", "Ch Font")
    @foreword.set_style_field!("zz_body", "font_size", 12)
    row_of(@foreword, "zz_body").update!(text_align: "center") # generator-only

    state = @foreword.style_state("zz_body")
    assert_equal %w[font_size text_align].sort, state[:changed_fields].sort
    assert_equal [ "font_size" ], state[:user_fields]
    assert_equal "Ch Font", state[:parent_values]["font"]
    assert_equal 10, state[:parent_values]["font_size"].to_i
    assert state[:has_parent]
    assert_equal row_of(@foreword, "zz_body"), state[:own]
  end

  test "operations touch this design so the controller's instance reflects the change" do
    before = @foreword.updated_at
    travel 1.second
    @foreword.set_style_field!("zz_body", "font_size", 11)
    assert_operator @foreword.updated_at, :>, before
    assert_equal @foreword.updated_at.to_i, @foreword.reload.updated_at.to_i
  end

  test "a chapter operation touches every doc type's designs" do
    befores = @forewords.map { |dd| dd.reload.updated_at }
    travel 1.second
    @chapter.set_style_field!("zz_body", "font_size", 11)
    @forewords.zip(befores).each { |dd, b| assert_operator dd.reload.updated_at, :>, b }
  end

  test "preview fingerprint changes after revert_style! deletes rows" do
    @foreword.set_style_field!("zz_body", "font_size", 11)
    before = fingerprint(@foreword)
    @foreword.revert_style!("zz_body")
    refute_equal before, fingerprint(@foreword)
  end

  test "preview fingerprint differs between two edits within the same second" do
    @foreword.set_style_field!("zz_body", "font_size", 11)
    first = fingerprint(@foreword)
    @foreword.set_style_field!("zz_body", "font_size", 12)
    refute_equal first, fingerprint(@foreword)
  end

  # ── proportional editing across paper sizes ─────────────────────────────

  test "a scaled field changes other sizes proportionally" do
    @theme.base_paragraph_styles.create!(name: "zz_title", font_size: 16)
    @chapters[0].paragraph_styles.create!(name: "zz_title", font_size: 18) # generator-style
    @chapters[1].paragraph_styles.create!(name: "zz_title", font_size: 24)

    @chapters[0].set_style_field!("zz_title", "font_size", 20)

    a, b = @chapters.map { |dd| row_of(dd, "zz_title") }
    assert_equal BigDecimal("20"), a.font_size
    assert_equal BigDecimal("26.67"), b.font_size
    [ a, b ].each { |row| assert_includes row.overridden_fields, "font_size" }
  end

  test "setting a size back to its inherited value reverts the field on every size" do
    @chapters[1].paragraph_styles.create!(name: "zz_body", font_size: 12)
    @forewords[0].set_style_field!("zz_body", "font_size", 11)
    assert_equal BigDecimal("13.2"), row_of(@forewords[1], "zz_body").font_size

    @forewords[0].set_style_field!("zz_body", "font_size", "10 ")

    @forewords.each { |dd| assert_nil row_of(dd, "zz_body") }
    state = @forewords[1].style_state("zz_body")
    assert_empty state[:changed_fields]
    assert_empty state[:user_fields]
  end

  test "non-scaled fields get the same value on every size" do
    @chapters[1].paragraph_styles.create!(name: "zz_body", font_size: 12, tracking: 2)
    @forewords[0].set_style_field!("zz_body", "text_color", "CMYK=0,100,0,0")
    @forewords[0].set_style_field!("zz_body", "tracking", 1)

    @forewords.each do |dd|
      row = row_of(dd, "zz_body")
      assert_equal "CMYK=0,100,0,0", row.text_color
      assert_equal BigDecimal("1"), row.tracking
      assert_equal %w[text_color tracking].sort, row.overridden_fields.sort
    end
  end

  test "a size with no resolved value for a scaled field gets the raw value" do
    @chapters[0].paragraph_styles.create!(name: "zz_body", left_indent: 4)

    @chapters[0].set_style_field!("zz_body", "left_indent", 6)

    assert_equal BigDecimal("6"), row_of(@chapters[0], "zz_body").left_indent
    assert_equal BigDecimal("6"), row_of(@chapters[1], "zz_body").left_indent
  end

  test "each size compares against its own parent" do
    @chapters[0].paragraph_styles.create!(name: "zz_body", font_size: 11)
    # chapter on size B has no zz_body row: foreword on B inherits 10 from the base

    @forewords[0].set_style_field!("zz_body", "font_size", 11)
    @forewords.each { |dd| assert_nil row_of(dd, "zz_body"), "equals A's parent → cleared everywhere" }

    @forewords[0].set_style_field!("zz_body", "font_size", 12)
    assert_equal BigDecimal("12"), row_of(@forewords[0], "zz_body").font_size
    assert_equal (BigDecimal("12") * 10 / 11).round(2), row_of(@forewords[1], "zz_body").font_size
  end

  test "a proportional target equal to that size's parent is cleared there, not stored" do
    @chapters[0].paragraph_styles.create!(name: "zz_body", font_size: 20)
    @chapters[1].paragraph_styles.create!(name: "zz_body", font_size: 10)
    @forewords[1].paragraph_styles.create!(name: "zz_body", font_size: 5, overridden_fields: [ "font_size" ])

    # A: 20 → 40 (×2); B: 5 → 10, which equals B's parent (chapter 10)
    @forewords[0].set_style_field!("zz_body", "font_size", 40)

    assert_equal BigDecimal("40"), row_of(@forewords[0], "zz_body").font_size
    assert_nil row_of(@forewords[1], "zz_body")
  end

  test "push_style! from a doc type scales chapter on the other sizes" do
    @chapters[1].paragraph_styles.create!(name: "zz_body", font_size: 15)
    @forewords[0].set_style_field!("zz_body", "font_size", 12)

    @forewords[0].push_style!("zz_body")

    assert_equal BigDecimal("12"), row_of(@chapters[0], "zz_body").font_size
    assert_equal BigDecimal("18"), row_of(@chapters[1], "zz_body").font_size
    @forewords.each { |dd| assert_nil row_of(dd, "zz_body") }
  end

  test "setting chapter back to its inherited value scales the other sizes instead of reverting them" do
    @theme.base_paragraph_styles.create!(name: "zz_title", font_size: 16)
    @chapters[0].paragraph_styles.create!(name: "zz_title", font_size: 18)
    @chapters[1].paragraph_styles.create!(name: "zz_title", font_size: 24)

    @chapters[0].set_style_field!("zz_title", "font_size", 16)

    assert_nil row_of(@chapters[0], "zz_title"), "this size equals the base → inherits (empty row deleted)"
    b = row_of(@chapters[1], "zz_title")
    assert_equal BigDecimal("21.33"), b.font_size, "24 × 16/18"
    assert_includes b.overridden_fields, "font_size"
  end

  test "setting chapter to the value it already inherits leaves the other sizes alone" do
    @theme.base_paragraph_styles.create!(name: "zz_title", font_size: 16)
    @chapters[1].paragraph_styles.create!(name: "zz_title", font_size: 24) # generator-style, unmarked

    @chapters[0].set_style_field!("zz_title", "font_size", 16)

    assert_nil row_of(@chapters[0], "zz_title")
    b = row_of(@chapters[1], "zz_title")
    assert_equal BigDecimal("24"), b.font_size
    assert_empty Array(b.overridden_fields), "untouched: not marked as a user change"
  end

  test "a chapter blank value still reverts the field on every size" do
    @theme.base_paragraph_styles.create!(name: "zz_title", font_size: 16)
    @chapters[0].set_style_field!("zz_title", "font_size", 20)

    @chapters[0].set_style_field!("zz_title", "font_size", "")

    @chapters.each { |dd| assert_nil row_of(dd, "zz_title") }
  end

  test "push_style! from chapter keeps the other sizes' scaled values" do
    @theme.base_paragraph_styles.create!(name: "zz_title", font_size: 16)
    @chapters[0].paragraph_styles.create!(name: "zz_title", font_size: 18)
    @chapters[1].paragraph_styles.create!(name: "zz_title", font_size: 24)
    @chapters[0].set_style_field!("zz_title", "font_size", 20)
    assert_equal BigDecimal("26.67"), row_of(@chapters[1], "zz_title").font_size

    @chapters[0].push_style!("zz_title")

    assert_equal BigDecimal("20"), @theme.base_paragraph_styles.find_by(name: "zz_title").font_size
    assert_nil row_of(@chapters[0], "zz_title"), "equals the new base → cleared"
    b = row_of(@chapters[1], "zz_title")
    assert_equal BigDecimal("26.67"), b.font_size, "B keeps its per-size value"
    assert_includes b.overridden_fields, "font_size"
  end

  test "a scaled target within rounding of a 3-decimal parent is cleared" do
    @theme.base_paragraph_styles.create!(name: "zz_title", font_size: 16)
    # B's parent (chapter on B) has 3 decimals.
    @chapters[1].paragraph_styles.create!(name: "zz_title", font_size: BigDecimal("16.667"))
    @forewords[0].paragraph_styles.create!(name: "zz_title", font_size: 36, overridden_fields: [ "font_size" ])
    @forewords[1].paragraph_styles.create!(name: "zz_title", font_size: 15, overridden_fields: [ "font_size" ])

    # A: 36 → 40; B: 15 × 40/36 = 16.666… → 16.67, 0.003 from its parent.
    @forewords[0].set_style_field!("zz_title", "font_size", 40)

    assert_equal BigDecimal("40"), row_of(@forewords[0], "zz_title").font_size
    assert_nil row_of(@forewords[1], "zz_title"), "16.67 vs parent 16.667 → within tolerance → inherits"
  end

  test "a string value goes through proportional scaling" do
    @theme.base_paragraph_styles.create!(name: "zz_title", font_size: 16)
    @chapters[0].paragraph_styles.create!(name: "zz_title", font_size: 18)
    @chapters[1].paragraph_styles.create!(name: "zz_title", font_size: 24)

    @chapters[0].set_style_field!("zz_title", "font_size", " 20 ")

    assert_equal BigDecimal("20"), row_of(@chapters[0], "zz_title").font_size
    assert_equal BigDecimal("26.67"), row_of(@chapters[1], "zz_title").font_size
  end

  test "a zero reference value falls back to the raw value on other sizes" do
    @chapters[0].paragraph_styles.create!(name: "zz_body", left_indent: 0)
    @chapters[1].paragraph_styles.create!(name: "zz_body", left_indent: 4)

    @chapters[0].set_style_field!("zz_body", "left_indent", 6)

    assert_equal BigDecimal("6"), row_of(@chapters[0], "zz_body").left_indent
    assert_equal BigDecimal("6"), row_of(@chapters[1], "zz_body").left_indent
  end

  test "push_style! from a doc type raises when a size lacks a chapter design" do
    ps3 = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    design_for(ps3, "foreword")
    ps3.document_designs.where(doc_type: "chapter").destroy_all
    @foreword.set_style_field!("zz_body", "font_size", 12)

    assert_raises(Design::DocumentDesign::MissingChapterError) { @foreword.push_style!("zz_body") }
    @chapters.each { |dd| assert_nil row_of(dd, "zz_body"), "nothing is written before the check" }
  end

  test "MissingChapterError names the sizes that lack a chapter" do
    @foreword.set_style_field!("zz_body", "text_align", "center")
    @chapters.last.destroy!
    error = assert_raises(Design::DocumentDesign::MissingChapterError) { @foreword.push_style!("zz_body") }
    assert_equal [ @ps2.display_name ], error.sizes
    assert_includes error.message, @ps2.display_name
  end

  test "style_exists? is true for a base, a chapter-only or an own row, false otherwise" do
    @chapter.paragraph_styles.create!(name: "zz_ch_only", font_size: 9)
    @foreword.paragraph_styles.create!(name: "zz_own_only", font_size: 9)

    assert @foreword.style_exists?("zz_body"), "theme base"
    assert @foreword.style_exists?("zz_ch_only"), "chapter-only, seen from foreword"
    assert @foreword.style_exists?("zz_own_only"), "own row"
    refute @foreword.style_exists?("zz_nowhere")
    refute @forewords.last.style_exists?("zz_ch_only"), "another size's chapter is not this size's parent"
    assert @chapter.style_exists?("zz_ch_only")
  end

  test "push_preview from chapter counts every other doc type keeping its own value" do
    prologue = design_for(@ps1, "prologue")
    prologue.paragraph_styles.create!(name: "zz_body", font_size: 13)
    @forewords[1].paragraph_styles.create!(name: "zz_body", font_size: 14)
    @chapter.set_style_field!("zz_body", "font_size", 12)

    assert_equal({ "font_size" => 2 }, @chapter.push_preview("zz_body"))
  end

  test "operations reset this design's cached style associations" do
    assert_empty @foreword.paragraph_styles.to_a.select { |r| r.name == "zz_body" }
    @foreword.set_style_field!("zz_body", "font_size", 11)
    assert @foreword.paragraph_styles.to_a.any? { |r| r.name == "zz_body" }, "association must not be stale"
  end

  test "preview fingerprint tracks the chapter layer" do
    before = fingerprint(@foreword)
    travel 1.second
    @chapter.paragraph_styles.create!(name: "zz_ch_only", font_size: 9)
    after_create = fingerprint(@foreword)
    refute_equal before, after_create, "a new chapter row must change the foreword preview"

    travel 1.second
    @chapter.paragraph_styles.find_by(name: "zz_ch_only").delete
    refute_equal after_create, fingerprint(@foreword), "a deleted chapter row must change the foreword preview"
  end

  private

  def design_for(ps, doc_type)
    ps.document_designs.find_by(doc_type: doc_type) || ps.document_designs.create!(doc_type: doc_type)
  end

  def row_of(dd, name) = dd.paragraph_styles.find_by(name: name)

  def fingerprint(dd) = Design::PreviewService.new(dd.reload).send(:cache_fingerprint)
end
