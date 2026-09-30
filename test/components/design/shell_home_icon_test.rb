require "test_helper"

# The studio bar's home link is an icon: the host's (Design.config.home_icon,
# a lambda evaluated in the view context like home_url), else a built-in house.
class Design::ShellHomeIconTest < ActiveSupport::TestCase
  # Fake view context: home_href resolves the home_url proc via
  # helpers.instance_exec, and falls back to helpers.themes_path when unset.
  # home_icon is similarly evaluated with helpers.instance_exec — a stubbed
  # helpers object needs no image_path since the icon lambda returns the URL.
  class FakeHelpers
    def themes_path = "/themes"
    def main_app = self
    def root_path = "/"
  end

  def render_shell
    shell = Design::Views::Shell.new(title: "X")
    shell.define_singleton_method(:helpers) { FakeHelpers.new }
    parent = Class.new(Design::Views::Base) do
      define_method(:initialize) { |s| @s = s }
      define_method(:view_template) { s = @s; render(s) { plain "BODY" } }
    end.new(shell)
    Nokogiri::HTML.fragment(parent.call)
  end

  teardown { Design.config.home_icon = nil }

  test "renders the configured icon with an accessible label" do
    Design.config.home_icon = -> { "/assets/app-icon.svg" }
    doc = render_shell
    link = doc.at_css("a.design-studio__home")
    assert_equal I18n.t("design.themes.home"), link["aria-label"]
    assert_equal "/assets/app-icon.svg", link.at_css("img")["src"]
    assert_empty link.text.strip, "no text: the icon is the link"
  end

  test "falls back to a built-in house icon" do
    link = render_shell.at_css("a.design-studio__home")
    assert link.at_css("svg"), "inline house svg"
    assert_equal I18n.t("design.themes.home"), link["aria-label"]
  end

  test "the Korean label is 홈" do
    assert_equal "홈", I18n.t("design.themes.home", locale: :ko)
  end
end
