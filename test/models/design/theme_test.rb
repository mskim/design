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
    theme.update!(imported_at: Time.current, source_file: "classic-ko.book_design")
    assert theme.imported?
  end

  test "a theme with a book_id is a book design, never system" do
    design = Design::Theme.create!(name: "BD #{SecureRandom.hex(3)}", locale: "ko", book_id: 7)

    assert design.book_design?
    assert_not design.system?
    assert_not Design::Theme.system_themes.exists?(design.id)
    assert_not Design::Theme.custom_themes.exists?(design.id)
    assert_not Design::Theme.starter_themes.exists?(design.id)
  end

  test "starter_themes holds system and custom themes" do
    system_theme = Design::Theme.create!(name: "S #{SecureRandom.hex(3)}", locale: "ko")
    custom = Design::Theme.create!(name: "C #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))

    assert_not system_theme.book_design?
    assert Design::Theme.starter_themes.exists?(system_theme.id)
    assert Design::Theme.starter_themes.exists?(custom.id)
  end

  test "book designs named like their starter are valid for different books" do
    Design::Theme.create!(name: "Classic", locale: "ko") unless Design::Theme.system_themes.exists?(name: "Classic", locale: "ko")

    a = Design::Theme.create!(name: "Classic", locale: "ko", book_id: 7)
    b = Design::Theme.new(name: "Classic", locale: "ko", book_id: 8)
    assert b.valid?, b.errors.full_messages.to_sentence
    b.save!

    assert_not Design::Theme.new(name: "Classic", locale: "ko", book_id: 7).valid?
    assert a.persisted?
  end

  test "a book design is never editable in the studio" do
    design = Design::Theme.create!(name: "BD #{SecureRandom.hex(3)}", locale: "ko", book_id: 7)
    assert_not design.editable_by?(users(:david))

    Design.configure { |c| c.authoring = true }
    assert_not design.editable_by?(users(:david))
  end

  test "export_dir and db_path: book designs under book_<id>, others unchanged" do
    design = Design::Theme.create!(name: "Classic", locale: "ko", book_id: 7)
    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko")
    custom = Design::Theme.create!(name: "Cus #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    base = Design.themes_dir

    assert_equal File.join(base, "book_7"), design.export_dir
    assert_equal File.join(base, "book_7", "classic-ko.db"), design.db_path

    assert_equal base, system_theme.export_dir
    assert_equal File.join(base, "#{system_theme.file_basename}.db"), system_theme.db_path

    assert_equal File.join(base, "user_#{users(:david).id}"), custom.export_dir
    assert_equal File.join(base, "user_#{users(:david).id}", "#{custom.file_basename}.db"), custom.db_path
  end
end
