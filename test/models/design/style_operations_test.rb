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
    travel 1.second
    @foreword.revert_style!("zz_body")
    refute_equal before, fingerprint(@foreword)
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
