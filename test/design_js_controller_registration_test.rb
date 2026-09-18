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

  # color-field / color-mode-field were replaced by design--color-row (ColorField).
  test "the old colour controllers are gone" do
    %w[color_field_controller.js color_mode_field_controller.js].each do |f|
      refute File.exist?(ENGINE_JS.join("design-controllers/design", f)), "#{f} should have been removed"
    end
  end

  # The Save/scope panel's controllers were replaced by design--style-autosave (D2b).
  test "the old panel save controllers are gone" do
    %w[panel_autosave_controller.js panel_save_response.js save_scope_controller.js].each do |f|
      refute File.exist?(ENGINE_JS.join("design-controllers/design", f)), "#{f} should have been removed"
    end
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

  # navigate-select controller (sidebar selects) — registers as design--navigate-select
  test "design/navigate_select_controller.js exists in design-controllers" do
    controller_path = ENGINE_JS.join("design-controllers/design/navigate_select_controller.js")
    assert File.exist?(controller_path),
      "Missing #{controller_path} — design--navigate-select controller will not load"
  end

  test "navigate_select controller visits the selected option's data-url" do
    src = File.read(ENGINE_JS.join("design-controllers/design/navigate_select_controller.js"))
    assert_includes src, %(import { Controller } from "@hotwired/stimulus")
    assert_includes src, "export default class"
    assert_includes src, "change(", "must define a change() action"
    assert_includes src, "dataset.url"
    assert_includes src, "Turbo.visit"
  end

  test "scrub_input controller exists and imports number_math by its importmap name" do
    src = File.read(ENGINE_JS.join("design-controllers/design/scrub_input_controller.js"))
    assert_includes src, %(import { Controller } from "@hotwired/stimulus")
    assert_includes src, %("design-controllers/design/number_math")
    %w[scrubStart( scrubMove( scrubEnd( keydown( commit( remember( handleClick( disconnect(].each { |m| assert_includes src, m }
    assert_includes src, 'dispatch("revert"', "resets must dispatch design--scrub-input:revert"
  end

  test "color_row controller exists and imports color_math by its importmap name" do
    src = File.read(ENGINE_JS.join("design-controllers/design/color_row_controller.js"))
    assert_includes src, %(import { Controller } from "@hotwired/stimulus")
    assert_includes src, %("design-controllers/design/color_math")
    %w[toggle( close( selectMode( fromChannels( fromSlider( fromHex( fromPicker( clear( keydown(].each { |m| assert_includes src, m }
  end

  test "color_row controller reverts the stored colour and closes on a document-level Escape" do
    src = File.read(ENGINE_JS.join("design-controllers/design/color_row_controller.js"))
    [ "revertField(", "rememberField(", 'addEventListener("keydown"', "showPicker" ].each { |m| assert_includes src, m }
    refute_match(/convert\s*[:=]/, src, "mode switch must not rewrite the stored value")
  end

  test "scrub_input re-syncs after a morph; color_row knows the parent colour" do
    assert_includes File.read(ENGINE_JS.join("design-controllers/design/scrub_input_controller.js")), "resync("
    src = File.read(ENGINE_JS.join("design-controllers/design/color_row_controller.js"))
    assert_includes src, "parent: String"
    assert_includes src, "parentValue"
  end

  test "border and corner editors dispatch a bubbling change and know the parent value" do
    %w[border_side_editor corner_editor].each do |c|
      src = File.read(ENGINE_JS.join("design-controllers/design/#{c}_controller.js"))
      assert_includes src, %(dispatchEvent(new Event("change", { bubbles: true }))), c
      assert_includes src, "parent: String", c
      assert_includes src, %("design-controllers/design/edge_flags"), c
      assert_includes src, "toggleFlag(", c
    end
  end

  test "style_autosave controller imports the queue by its importmap name and renders streams" do
    src = File.read(ENGINE_JS.join("design-controllers/design/style_autosave_controller.js"))
    assert_includes src, %(import { Controller } from "@hotwired/stimulus")
    assert_includes src, %("design-controllers/design/style_save_queue")
    assert_includes src, %("design-controllers/design/style_panel_morph")
    %w[fieldChanged( revert( revertStyle( pushStyle( ignoreSubmit( keepLocalState( keepOpenPopover( send( reloadPreview( closeMenu( disconnect(].each { |m| assert_includes src, m }
    assert_includes src, "previewUrl: String"
    assert_includes src, "window.Turbo.renderStreamMessage"
    refute_match(/from\s+["']\.\.?\//, src, "no relative imports (importmap)")
  end

  # A save's morph must not reset the ▾ menu the user opened, a <details>' open
  # state or the Page section's link: one pure rule (node-tested) decides.
  test "style_autosave keeps user-set attributes through a morph via keepsUserAttribute" do
    src = File.read(ENGINE_JS.join("design-controllers/design/style_autosave_controller.js"))
    assert_match(/keepsUserAttribute\(el, attributeName\)/, src)
    morph = File.read(ENGINE_JS.join("design-controllers/design/style_panel_morph.js"))
    assert_includes morph, %(export const MENU = "[data-design--dropdown-target='menu']")
    assert_includes morph, %(export const MARGIN_LINK = "[data-margin-link]")
  end

  test "style_autosave is configurable (prefix, panel target, required fields) and saves through saveJobs" do
    src = File.read(ENGINE_JS.join("design-controllers/design/style_autosave_controller.js"))
    assert_includes src, %("design-controllers/design/field_save_jobs")
    assert_includes src, "fieldPrefix: { type: String, default: FIELD_PREFIX }"
    assert_includes src, "panelTarget: { type: String, default: PANEL_TARGET }"
    assert_includes src, "requiredFields: Array"
    assert_includes src, "withoutStreamsFor(html, this.panelTargetValue)"
    assert_includes src, "getElementById(this.panelTargetValue)"
    %w[toggleLink( mirrorPartner( enqueueAll(].each { |m| assert_includes src, m }
    assert_includes src, "values["
  end

  # The morph decision is taken once per element, before Idiomorph touches its
  # attributes (it asks about `value` twice); the listener is added in connect(),
  # so the form's data-action needs no entry for it.
  test "style_autosave decides a control's local value on turbo:before-morph-element" do
    src = File.read(ENGINE_JS.join("design-controllers/design/style_autosave_controller.js"))
    assert_includes src, 'addEventListener("turbo:before-morph-element"'
    assert_includes src, 'removeEventListener("turbo:before-morph-element"'
    assert_includes src, "LocalValueKeeper"
  end

  %w[style_save_queue style_panel_morph edge_flags field_save_jobs].each do |mod|
    test "#{mod} is a pure module" do
      src = File.read(ENGINE_JS.join("design-controllers/design/#{mod}.js"))
      refute_match(/^import /, src)
      refute_includes src, "document."
      refute_includes src, "window."
    end
  end

  test "live_preview ignores the Page section's events (they bubble through the tabs form)" do
    assert_includes File.read(ENGINE_JS.join("design-controllers/design/live_preview_controller.js")),
                    %(closest?.("[data-page-section]"))
  end
end
