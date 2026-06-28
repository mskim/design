# engines/design/test/models/design/theme_test.rb
require "test_helper"

class Design::ThemeTest < ActiveSupport::TestCase
  test "after_create seeds 5 table_styles + 2 cell paragraph_styles" do
    theme = Design::Theme.create!(name: "T #{SecureRandom.hex(3)}", locale: "ko")
    assert_equal 5, theme.table_styles.count
    assert theme.base_paragraph_styles.exists?(name: "table_heading_cell")
    assert theme.base_paragraph_styles.exists?(name: "table_body_cell")
  end

  test "editable_by? — designers edit any custom theme; system themes are always read-only" do
    david = users(:david) # admin → can_design?
    jz    = users(:jz)     # writer → !can_design?

    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko") # user_id nil
    my_custom    = Design::Theme.create!(name: "Mine #{SecureRandom.hex(3)}", locale: "ko", user_id: david.id)
    other_custom = Design::Theme.create!(name: "Other #{SecureRandom.hex(3)}", locale: "ko", user_id: jz.id)

    assert system_theme.system?

    # Non-designers ("users just use themes") can edit nothing.
    assert_not my_custom.editable_by?(jz)
    assert_not system_theme.editable_by?(jz)
    assert_not my_custom.editable_by?(nil)

    # Designers edit ANY custom theme (shared across the one house's designers).
    assert my_custom.editable_by?(david)
    assert other_custom.editable_by?(david)

    # System themes are ALWAYS read-only in book_write (authoring=false default).
    assert_not system_theme.editable_by?(david)
  end

  test "editable_by? — system theme becomes editable when Design.authoring? is true" do
    david = users(:david) # admin → can_design?

    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko")
    original_authoring = Design.config.authoring

    begin
      Design.configure { |c| c.authoring = true }
      assert system_theme.editable_by?(david), "system theme should be editable when authoring=true"
      # user arg is irrelevant for system themes when authoring=true
      assert system_theme.editable_by?(nil), "authoring=true bypasses user check for system themes"
    ensure
      Design.configure { |c| c.authoring = original_authoring }
    end
  end

  test "imported? is true once import provenance is stamped" do
    theme = Design::Theme.create!(name: "prov #{SecureRandom.hex(3)}", locale: "ko")
    assert_not theme.imported?
    theme.update!(imported_at: Time.current, source_file: "seoul.book_design")
    assert theme.imported?
  end

  test "apply_paragraph_style_to_doc_type! writes an override to every same-doc_type design and leaves base + other doc_types alone" do
    theme = Design::Theme.create!(name: "FT #{SecureRandom.hex(3)}", locale: "ko")
    s1 = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    s2 = theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
    ch1 = s1.document_designs.create!(doc_type: "chapter")
    ch2 = s2.document_designs.create!(doc_type: "chapter")
    poem = s1.document_designs.create!(doc_type: "poem")
    theme.base_paragraph_styles.create!(name: "body", font_size: 10)

    theme.apply_paragraph_style_to_doc_type!("chapter", "body", { "font_size" => "13" })

    assert_equal "13.0", ch1.paragraph_styles.find_by(name: "body").font_size.to_s
    assert_equal "13.0", ch2.paragraph_styles.find_by(name: "body").font_size.to_s
    assert_nil poem.paragraph_styles.find_by(name: "body"), "other doc_types untouched"
    assert_equal 10, theme.base_paragraph_styles.find_by(name: "body").font_size, "base untouched"
  end

  test "apply_paragraph_style_to_doc_type! is idempotent (upsert, no duplicate rows)" do
    theme = Design::Theme.create!(name: "FT #{SecureRandom.hex(3)}", locale: "ko")
    s1 = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ch1 = s1.document_designs.create!(doc_type: "chapter")
    theme.apply_paragraph_style_to_doc_type!("chapter", "body", { "font_size" => "13" })
    theme.apply_paragraph_style_to_doc_type!("chapter", "body", { "font_size" => "15" })
    assert_equal 1, ch1.paragraph_styles.where(name: "body").count
    assert_equal "15.0", ch1.paragraph_styles.find_by(name: "body").font_size.to_s
  end

  test "apply_paragraph_style_to_all! upserts the base (creating it when absent) and clears same-name overrides theme-wide" do
    theme = Design::Theme.create!(name: "FA #{SecureRandom.hex(3)}", locale: "ko")
    s1 = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ch1 = s1.document_designs.create!(doc_type: "chapter")
    poem = s1.document_designs.create!(doc_type: "poem")
    ch1.paragraph_styles.create!(name: "wing_left", font_size: 8)   # override-only style, no base row
    poem.paragraph_styles.create!(name: "wing_left", font_size: 9)

    theme.apply_paragraph_style_to_all!("wing_left", { "font_size" => "20" })

    base = theme.base_paragraph_styles.find_by(name: "wing_left")
    assert_not_nil base, "base row created when none existed"
    assert_equal "20.0", base.font_size.to_s
    assert_equal 0, ch1.paragraph_styles.where(name: "wing_left").count, "shadowing overrides cleared"
    assert_equal 0, poem.paragraph_styles.where(name: "wing_left").count
  end

  test "shadow_override_doc_types returns distinct doc_types (one per doc_type, not per row)" do
    theme = Design::Theme.create!(name: "SH #{SecureRandom.hex(3)}", locale: "ko")
    s1 = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    s2 = theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
    s1.document_designs.create!(doc_type: "chapter").paragraph_styles.create!(name: "body")
    s2.document_designs.create!(doc_type: "chapter").paragraph_styles.create!(name: "body")
    s1.document_designs.create!(doc_type: "poem").paragraph_styles.create!(name: "body")

    result = theme.shadow_override_doc_types("body")
    assert_equal %w[chapter poem], result.sort
  end

end
