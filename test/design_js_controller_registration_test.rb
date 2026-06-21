require "test_helper"

# Guards against "tabs look right but don't switch" by verifying the
# ruby-ui--tabs Stimulus controller is present where eagerLoadControllersFrom
# will discover and register it.
#
# eagerLoadControllersFrom("design-controllers", application) converts:
#   design-controllers/ruby-ui/tabs_controller.js  →  identifier "ruby-ui--tabs"
# (strips prefix, removes _controller, replaces "/" with "--", replaces "_" with "-")
#
# The importmap's pin_all_from "engines/design/app/javascript/design-controllers"
# makes that module available as "design-controllers/ruby-ui/tabs_controller".
class DesignJsControllerRegistrationTest < ActiveSupport::TestCase
  ENGINE_JS = Design::Engine.root.join("app/javascript")
  HOST_IMPORTMAP = Rails.root.join("config/importmap.rb")

  test "ruby-ui/tabs_controller.js exists in design-controllers" do
    controller_path = ENGINE_JS.join("design-controllers/ruby-ui/tabs_controller.js")
    assert File.exist?(controller_path),
      "Missing #{controller_path} — ruby-ui--tabs controller will not load"
  end

  test "ruby-ui tabs controller exports a Stimulus Controller class" do
    src = File.read(ENGINE_JS.join("design-controllers/ruby-ui/tabs_controller.js"))
    assert_includes src, "import { Controller } from \"@hotwired/stimulus\""
    assert_includes src, "export default class"
    assert_includes src, "ruby-ui--tabs"
  end

  test "host importmap pins design-controllers prefix covering ruby-ui subdir" do
    importmap = File.read(HOST_IMPORTMAP)
    assert_match(/pin_all_from.*design-controllers/, importmap)
  end

  test "design index.js uses eagerLoadControllersFrom design-controllers" do
    index_src = File.read(ENGINE_JS.join("design/index.js"))
    assert_includes index_src, %(eagerLoadControllersFrom("design-controllers", application)),
      "index.js must call eagerLoadControllersFrom so ruby-ui--tabs is auto-registered"
  end

  # color-field controller (ported from book_design) — registers as design--color-field
  test "design/color_field_controller.js exists in design-controllers" do
    controller_path = ENGINE_JS.join("design-controllers/design/color_field_controller.js")
    assert File.exist?(controller_path),
      "Missing #{controller_path} — design--color-field controller will not load"
  end

  test "color_field controller exports a Stimulus Controller class" do
    src = File.read(ENGINE_JS.join("design-controllers/design/color_field_controller.js"))
    assert_includes src, %(import { Controller } from "@hotwired/stimulus")
    assert_includes src, "export default class"
    assert_includes src, "static targets"
  end

  # toggle-visibility controller (written from scratch) — registers as design--toggle-visibility
  test "design/toggle_visibility_controller.js exists in design-controllers" do
    controller_path = ENGINE_JS.join("design-controllers/design/toggle_visibility_controller.js")
    assert File.exist?(controller_path),
      "Missing #{controller_path} — design--toggle-visibility controller will not load"
  end

  test "toggle_visibility controller exports a Stimulus Controller class" do
    src = File.read(ENGINE_JS.join("design-controllers/design/toggle_visibility_controller.js"))
    assert_includes src, %(import { Controller } from "@hotwired/stimulus")
    assert_includes src, "export default class"
    assert_includes src, "static targets"
  end

  test "toggle_visibility controller has a content target and toggle action" do
    src = File.read(ENGINE_JS.join("design-controllers/design/toggle_visibility_controller.js"))
    assert_includes src, %("content"), "must declare content as a target"
    assert_includes src, "toggle(", "must define a toggle() action"
    assert_includes src, "classList.toggle", "must toggle the hidden class"
  end
end
