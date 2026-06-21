require "test_helper"

class RubyUiRenderTest < ActiveSupport::TestCase
  test "vendored RubyUI components render HTML" do
    assert_includes RubyUI::Button.new { "Save" }.call, "<button"
    assert_includes RubyUI::Button.new { "Save" }.call, "Save"
    assert_includes RubyUI::Card.new { "body" }.call, "rounded-xl"
    assert_includes RubyUI::Badge.new { "system" }.call, "<span"
  end

  test "engine Phlex base resolves" do
    assert Design::Views::Base < Phlex::HTML
  end
end
