require "test_helper"

class RubyUiTabsTest < ActiveSupport::TestCase
  test "Tabs renders data-controller ruby-ui--tabs" do
    html = RubyUI::Tabs.new(default: "tab1") { }.call
    assert_includes html, %(data-controller="ruby-ui--tabs")
  end

  test "Tabs renders active value attribute" do
    html = RubyUI::Tabs.new(default: "tab1") { }.call
    assert_includes html, %(data-ruby-ui--tabs-active-value="tab1")
  end

  test "TabsList renders wrapper div with flex classes" do
    html = RubyUI::TabsList.new { }.call
    assert_includes html, "<div"
    assert_includes html, "inline-flex"
  end

  test "TabsTrigger renders button with correct data attributes" do
    html = RubyUI::TabsTrigger.new(value: "tab1") { "Label" }.call
    assert_includes html, "<button"
    assert_includes html, %(data-ruby-ui--tabs-target="trigger")
    assert_includes html, "click->ruby-ui--tabs#show"
    assert_includes html, %(data-value="tab1")
    assert_includes html, "Label"
  end

  test "TabsContent renders panel div with correct data attributes" do
    html = RubyUI::TabsContent.new(value: "tab1") { "Content" }.call
    assert_includes html, "<div"
    assert_includes html, %(data-ruby-ui--tabs-target="content")
    assert_includes html, %(data-value="tab1")
    assert_includes html, "Content"
    assert_includes html, "hidden"
  end

  # Composite test using a Phlex component to verify render composition
  class TabsComposite < Phlex::HTML
    def view_template
      render RubyUI::Tabs.new(default: "tab1") do
        render RubyUI::TabsList.new do
          render RubyUI::TabsTrigger.new(value: "tab1") { "Tab One" }
          render RubyUI::TabsTrigger.new(value: "tab2") { "Tab Two" }
        end
        render RubyUI::TabsContent.new(value: "tab1") { "Panel One" }
        render RubyUI::TabsContent.new(value: "tab2") { "Panel Two" }
      end
    end
  end

  test "full Tabs composite renders controller and trigger and panel" do
    html = TabsComposite.new.call
    assert_includes html, %(data-controller="ruby-ui--tabs")
    assert_includes html, "Tab One"
    assert_includes html, "Tab Two"
    assert_includes html, "Panel One"
    assert_includes html, "Panel Two"
    assert_includes html, %(data-ruby-ui--tabs-target="trigger")
    assert_includes html, %(data-ruby-ui--tabs-target="content")
  end
end
