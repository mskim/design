require "test_helper"

# Art-style themes: the name says the style, `locale` says the language. One
# style exists once per language, files are named <style>-<locale>, and the
# default theme is the system Classic in the book's language.
class Design::ThemeNamingTest < ActiveSupport::TestCase
  def system_theme(name, locale = "ko") = Design::Theme.create!(name: name, locale: locale)

  test "file_basename is the parameterized name plus the locale" do
    assert_equal "classic-ko", Design::Theme.new(name: "Classic", locale: "ko").file_basename
    assert_equal "avant-garde-ko", Design::Theme.new(name: "Avant-garde", locale: "ko").file_basename
    assert_equal "classic-en", Design::Theme.new(name: "classic", locale: "en").file_basename
  end

  test "a name that parameterizes to nothing falls back to the id" do
    theme = system_theme("우리출판사 #{SecureRandom.hex(2)}".delete("0-9a-f"))
    assert_equal "theme-#{theme.id}-ko", theme.file_basename
  end

  test "the same style may exist once per language" do
    system_theme("Classic", "ko")
    assert Design::Theme.new(name: "Classic", locale: "en").valid?
    dup = Design::Theme.new(name: "Classic", locale: "ko")
    refute dup.valid?
    assert dup.errors.of_kind?(:name, :taken)
  end

  test "default_for finds the system Classic in that language, whatever its case" do
    ko = system_theme("Classic", "ko")
    en = system_theme("classic", "en")
    system_theme("Modern", "ko")
    assert_equal ko, Design::Theme.default_for("ko")
    assert_equal en, Design::Theme.default_for("en")
    assert_equal ko, Design::Theme.default_for, "no language means Korean"
  end

  test "default_for falls back to the Korean Classic, then nil" do
    ko = system_theme("Classic", "ko")
    assert_equal ko, Design::Theme.default_for("ja")
    ko.destroy
    assert_nil Design::Theme.default_for("ja")
  end

  test "a custom theme named Classic is never the default" do
    user = Design.config.user_class.constantize.first || skip("dummy app has no users")
    Design::Theme.create!(name: "Classic", locale: "ko", user_id: user.id)
    assert_nil Design::Theme.default_for("ko")
  end
end
