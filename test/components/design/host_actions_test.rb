require "test_helper"

class Design::HostActionsTest < ActiveSupport::TestCase
  # Minimal component that renders a slot.
  class Probe < Design::Views::Base
    def initialize(slot:, context: nil) = (@slot = slot; @context = context)
    def view_template = render_host_actions(@slot, @context)
  end

  # Fake view context: instance_exec re-binds the block to THIS, where main_app exists.
  class FakeHelpers
    Routes = Struct.new(:nil) { def export_theme_db_path(t) = "/themes/#{t}/export" }
    def main_app = Routes.new
  end

  def render(slot:, context: nil)
    c = Probe.new(slot: slot, context: context)
    c.define_singleton_method(:helpers) { FakeHelpers.new }
    c.call
  end

  # Design.config.dup (in test_helper) is shallow and shares the ActionRegistry, so the global restore doesn't clear registrations — force a fresh registry here.
  teardown { Design.config.instance_variable_set(:@actions, nil) }  # reset registry

  test "renders a registered GET descriptor as a link with the host-route path" do
    Design.config.actions.for(:t) { |theme| [{ label: "Export", path: main_app.export_theme_db_path(theme), method: :get }] }
    html = render(slot: :t, context: 7)
    assert_includes html, "Export"
    assert_includes html, %(href="/themes/7/export")   # main_app resolved at render time
  end

  test "renders nothing for an unregistered slot" do
    assert_equal "", render(slot: :missing).strip
  end

  test "block arity 0 also works" do
    Design.config.actions.for(:t0) { [{ label: "New", path: "/new", method: :get }] }
    assert_includes render(slot: :t0), "New"
  end

  test "non-GET descriptor renders via button_to with method + turbo_confirm" do
    Design.config.actions.for(:del) { [{ label: "Delete", path: "/x", method: :delete, confirm: "Sure?" }] }
    captured = {}
    c = Probe.new(slot: :del)
    c.define_singleton_method(:helpers) { FakeHelpers.new }
    # button_to is a component method (Phlex::Rails::Helpers::ButtonTo), so a
    # singleton override on the instance intercepts the non-GET dispatch.
    c.define_singleton_method(:button_to) do |label, path, **opts|
      captured.merge!(label: label, path: path, method: opts[:method], confirm: opts.dig(:data, :turbo_confirm))
      plain label  # emit something so the render is non-empty
    end
    html = c.call
    assert_includes html, "Delete"
    assert_equal :delete, captured[:method]
    assert_equal "Sure?", captured[:confirm]
    assert_equal "/x", captured[:path]
  end
end
