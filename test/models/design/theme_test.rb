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

end
