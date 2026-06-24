require "test_helper"

class Design::ShellTest < ActiveSupport::TestCase
  class Sidebar < Design::Views::Base
    def view_template = div(class: "sidebar-probe") { "SIDE" }
  end

  # Fake view context: home_href resolves the home_url proc via
  # helpers.instance_exec, and falls back to helpers.themes_path when unset. The
  # dummy app sets home_url to `-> { main_app.root_path }`, so stub all three.
  class FakeHelpers
    def themes_path = "/themes"
    def main_app = self
    def root_path = "/"
  end

  def shell(**opts, &block)
    blk = block || proc { plain "MAIN" }
    # The Shell is the component that calls `helpers` (in home_href /
    # render_host_actions), so stub helpers on the Shell instance itself.
    shell = Design::Views::Shell.new(**opts)
    shell.define_singleton_method(:helpers) { FakeHelpers.new }
    parent = Class.new(Design::Views::Base) do
      define_method(:initialize) { |s, b| @s = s; @b = b }
      # block to render(...), NOT to Shell.new — Phlex 2.4.1 only renders the
      # block when it's passed to render and consumed via yield in the Shell.
      # In real call sites the body block is authored inside a Phlex view, so
      # markup helpers (plain/div/…) resolve against that view. Re-exec the
      # caller's block here so the bare `plain "BODY"` in the tests resolves.
      define_method(:view_template) { b = @b; render(@s) { instance_exec(&b) } }
    end.new(shell, blk)
    parent.call
  end

  test "renders top bar with title + yielded main" do
    html = shell(title: "Seoul") { plain "BODY" }
    assert_includes html, "Seoul"
    assert_includes html, "BODY"
  end

  test "renders the sidebar component when given" do
    html = shell(title: "X", sidebar: Sidebar.new) { plain "M" }
    assert_includes html, "sidebar-probe"
    assert_includes html, "SIDE"
  end

  test "omits the sidebar column when nil" do
    html = shell(title: "X", sidebar: nil) { plain "M" }
    refute_includes html, "sidebar-probe"
  end
end
