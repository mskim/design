# Studio Shell + Host-Extension Contract — Implementation Plan (Sub-project 0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Give the gem's design studio a persistent shell (top bar + optional contextual sidebar) styled to match book_design exactly, plus a declarative host-action registry so hosts inject their host-only buttons — the foundation for porting book_design's UI into the gem.

**Architecture:** A `Design::ActionRegistry` on `Design.config.actions` stores host blocks (raw, not called); a `render_host_actions` helper in `Design::Views::Base` re-binds each block in the Phlex view (`helpers.instance_exec`, so `main_app.*` host routes resolve) and renders the returned button descriptors. A `Design::Views::Shell` component provides the chrome; the 4 existing studio views are re-housed in it. book_design registers its host actions in an initializer.

**Tech Stack:** Rails 8.1 engine, Phlex components, RubyUI, Minitest, scoped Tailwind build.

**Spec:** `design/docs/superpowers/specs/2026-06-24-studio-shell-host-extension-design.md`

**Repo:** `DG = /Users/mskim/Development/ruby/gems/design` (gem, branch `main`) — Tasks 1–4. `BD = /Users/mskim/Development/book/book_design` — Task 5.

**Conventions (verified):**
- `Design::Configuration` (`lib/design.rb`) holds host hooks via `attr_accessor`; `Design.config` = memoized instance. Add an `actions` registry.
- `Design::Views::Base` (`app/components/design/views/base.rb`) is a `Phlex::HTML` including `Phlex::Rails::Helpers::Routes/ButtonTo/TurboFrameTag` + `RubyUI`. Host routes resolve via `helpers.main_app.*` (engine is `isolate_namespace Design`).
- The existing home-link pattern is `helpers.instance_exec(&Design.config.home_url)` (`themes/index.rb:25`) — the registry uses the same `instance_exec` binding.
- Component tests live in `test/components/design/`, `ActiveSupport::TestCase`, render a component by instantiating it, stubbing `helpers.*` via `define_singleton_method`, and calling `.call` (returns HTML string). Integration tests (`test/controllers/design/*`) GET engine routes (e.g. `design.themes_path`).
- The gem's CSS is the scoped build `app/assets/builds/design.css` (from `app/assets/tailwind/design.css`, `source(none)` + `@source "../../components/**"`). Rebuild it with the runner in Task 3; `DesignTailwindBuildFreshnessTest` compares committed vs fresh.
- **Descriptors use blocks, never lambdas** (arity tolerance: `instance_exec(context, &block)` passes context; a `do…end` block ignores an extra arg, a lambda would raise).
- Minitest only. Commit to `main`. Do NOT push (a later step / the user handles pushing). Leave `Gemfile.lock` unstaged.

---

## File Structure

**`DG` (gem):**
- Create `lib/design/action_registry.rb` — `Design::ActionRegistry` (`for`/`resolve`, stores raw blocks).
- Modify `lib/design.rb` — `require` it; add `Configuration#actions`.
- Modify `app/components/design/views/base.rb` — add `render_host_actions`, `render_action_descriptor`, `shell` convenience.
- Create `app/components/design/views/shell.rb` — `Design::Views::Shell` (top bar + sidebar slot + main).
- Modify the 4 studio views: `themes/index.rb`, `themes/show.rb`, `paper_sizes/edit.rb`, `document_designs/edit.rb` — re-house in `Shell`.
- Rebuild `app/assets/builds/design.css`.
- Tests: `test/design/action_registry_test.rb`, `test/components/design/host_actions_test.rb`, `test/components/design/shell_test.rb`, `test/controllers/design/studio_shell_test.rb`.

**`BD` (host) — Task 5:**
- Modify `config/initializers/design.rb` — register `themes_index` + `theme_show` action descriptors.
- Test: `test/integration/studio_host_actions_test.rb`.

---

## Task 1 — `Design::ActionRegistry` + `Design.config.actions`

**Files:** Create `DG/lib/design/action_registry.rb`; modify `DG/lib/design.rb`; create `DG/test/design/action_registry_test.rb`.

- [ ] **Step 1: Write the failing test** `DG/test/design/action_registry_test.rb`:
```ruby
require "test_helper"

class Design::ActionRegistryTest < ActiveSupport::TestCase
  setup { @reg = Design::ActionRegistry.new }

  test "for stores a block, resolve returns it" do
    blk = ->(theme) { [{ label: "X", path: "/x" }] }
    @reg.for(:theme_show, &blk)
    assert_equal blk, @reg.resolve(:theme_show)
  end

  test "resolve returns nil for an unregistered slot" do
    assert_nil @reg.resolve(:nope)
  end

  test "string and symbol slot names are interchangeable" do
    @reg.for("theme_show") { [] }
    assert_not_nil @reg.resolve(:theme_show)
  end

  test "Design.config.actions is a memoized ActionRegistry" do
    assert_instance_of Design::ActionRegistry, Design.config.actions
    assert_same Design.config.actions, Design.config.actions
  end
end
```

- [ ] **Step 2: Run it; verify it FAILS** — `cd /Users/mskim/Development/ruby/gems/design && bin/rails test test/design/action_registry_test.rb` (uninitialized constant / no `actions`).

- [ ] **Step 3: Implement.** Create `DG/lib/design/action_registry.rb`:
```ruby
module Design
  # Stores host-registered action blocks per named slot. Blocks are stored RAW
  # (not called) — a block binds to its definition site (an initializer with no
  # view context), so it must be re-bound at render time via instance_exec in the
  # Phlex view (see Design::Views::Base#render_host_actions).
  class ActionRegistry
    def for(slot, &block) = registrations[slot.to_sym] = block
    def resolve(slot)     = registrations[slot.to_sym]

    private

    def registrations = @registrations ||= {}
  end
end
```
In `DG/lib/design.rb`: add `require_relative "design/action_registry"` near the top `require_relative` lines, and add to `Configuration`:
```ruby
    def actions = @actions ||= Design::ActionRegistry.new
```
(Place it as a method in `Configuration` after `initialize`.)

- [ ] **Step 4: Run the test; verify it PASSES.**

- [ ] **Step 5: Commit:**
```bash
cd /Users/mskim/Development/ruby/gems/design
git add lib/design/action_registry.rb lib/design.rb test/design/action_registry_test.rb
git commit -m "feat(studio): Design::ActionRegistry + config.actions"
```

---

## Task 2 — `render_host_actions` in `Design::Views::Base`

**Files:** Modify `DG/app/components/design/views/base.rb`; create `DG/test/components/design/host_actions_test.rb`.

> The crux: a registered block must resolve host routes at RENDER time. We re-bind it with `helpers.instance_exec(context, &block)`, exactly like the existing `home_url` usage. The test proves a descriptor whose `path:` calls `main_app.*` resolves — by stubbing `helpers` with a fake that exposes `main_app`.

- [ ] **Step 1: Write the failing test** `DG/test/components/design/host_actions_test.rb`:
```ruby
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
end
```
> NOTE: this covers the GET-link path + the render-time `main_app` binding (the make-or-break detail) without needing a real view context. The non-GET `button_to` path + full chrome are covered by the integration test in Task 4 (real view context). If `Design.config` is shared global state, the `teardown` reset prevents leakage; confirm `Design.config` is a singleton and reset `@actions` between tests as shown.

- [ ] **Step 2: Run it; verify it FAILS** — `bin/rails test test/components/design/host_actions_test.rb` (`render_host_actions` undefined).

- [ ] **Step 3: Implement** in `DG/app/components/design/views/base.rb` (add methods to the class):
```ruby
      # Render the host-registered actions for a slot. The block is re-bound to the
      # view context so host routes (main_app.*) resolve at render time.
      def render_host_actions(slot, context = nil)
        block = Design.config.actions.resolve(slot) or return
        Array(helpers.instance_exec(context, &block)).each { |d| render_action_descriptor(d) }
      end

      def render_action_descriptor(d)
        method = (d[:method] || :get).to_sym
        data = {}
        data[:turbo_confirm] = d[:confirm] if d[:confirm]
        if method == :get
          a(href: d[:path], class: action_button_class, data: data) { d[:label] }
        else
          button_to(d[:label], d[:path], method: method, class: action_button_class, data: data)
        end
      end

      # Shared button styling — matched to book_design's action buttons in Task 3.
      def action_button_class = "inline-flex items-center gap-1 rounded-md px-3 py-1.5 text-sm font-medium border border-slate-300 hover:bg-slate-50"
```

- [ ] **Step 4: Run the test; verify it PASSES.**

- [ ] **Step 5: Commit:**
```bash
git add app/components/design/views/base.rb test/components/design/host_actions_test.rb
git commit -m "feat(studio): render_host_actions (render-time main_app binding)"
```

---

## Task 3 — `Design::Views::Shell` component (+ styling, CSS rebuild)

**Files:** Create `DG/app/components/design/views/shell.rb`; modify `DG/app/components/design/views/base.rb` (add `shell` convenience); rebuild `DG/app/assets/builds/design.css`; create `DG/test/components/design/shell_test.rb`.

> Build the chrome with **the same explicit utility classes book_design uses** so it matches exactly. Reference book_design's chrome: `BD/app/components/pages/themes/show.rb` (top action bar) and `BD/app/components/pages/paper_sizes/show.rb` (sidebar). Copy the container/border/spacing classes verbatim (e.g. `min-h-screen`, `border-b`, `px-6 py-4`, `w-64`, etc.). Do NOT author token CSS.

- [ ] **Step 1: Write the failing test** `DG/test/components/design/shell_test.rb`:
```ruby
require "test_helper"

class Design::ShellTest < ActiveSupport::TestCase
  class Sidebar < Design::Views::Base
    def view_template = div(class: "sidebar-probe") { "SIDE" }
  end

  def shell(**opts, &block)
    c = Class.new(Design::Views::Base) do
      define_method(:initialize) { |o, b| @o = o; @b = b }
      define_method(:view_template) { render Design::Views::Shell.new(**@o, &@b) }
    end.new(opts, block || proc { plain "MAIN" })
    c.define_singleton_method(:helpers) { o = Object.new; def o.instance_exec(*); end; o }
    c.call
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
```
> Adjust the render harness to whatever the gem's existing component tests use to render a parent that `render`s a child (mirror `properties_panel_test.rb`'s approach if this anonymous-class form fights the test setup). The `helpers` stub here only needs to no-op `instance_exec` since the title/sidebar paths don't hit host actions; pass `action_slot: nil` so `render_host_actions` returns early.

- [ ] **Step 2: Run it; verify it FAILS** (`Design::Views::Shell` uninitialized).

- [ ] **Step 3: Implement** `DG/app/components/design/views/shell.rb`:
```ruby
module Design
  module Views
    class Shell < Design::Views::Base
      def initialize(title:, breadcrumb: nil, action_slot: nil, action_context: nil, sidebar: nil, &block)
        @title = title
        @breadcrumb = breadcrumb
        @action_slot = action_slot
        @action_context = action_context
        @sidebar = sidebar
        @body = block
      end

      def view_template
        div(class: "design-studio flex min-h-screen flex-col") do
          top_bar
          div(class: "flex flex-1 min-h-0") do
            if @sidebar
              aside(class: "w-64 shrink-0 overflow-y-auto border-r border-slate-200") { render @sidebar }
            end
            main(class: "flex-1 overflow-y-auto") { @body&.call }
          end
        end
      end

      private

      def top_bar
        header(class: "flex items-center justify-between gap-4 border-b border-slate-200 px-6 py-4") do
          div(class: "flex items-center gap-3 min-w-0") do
            a(href: home_href, class: "text-sm text-blue-600 hover:underline shrink-0") { I18n.t("design.themes.index_title") }
            span(class: "truncate text-lg font-semibold") { @breadcrumb || @title }
          end
          div(class: "flex items-center gap-2 shrink-0") { render_host_actions(@action_slot, @action_context) if @action_slot }
        end
      end

      def home_href
        url = Design.config.home_url
        url ? helpers.instance_exec(&url) : helpers.themes_path
      end
    end
  end
end
```
> Replace the placeholder chrome classes (`border-slate-200`, `px-6 py-4`, etc.) with book_design's exact classes from `pages/themes/show.rb` / `pages/paper_sizes/show.rb` so the look matches. `@body&.call` renders the Phlex block content (confirm Phlex block-capture form against the gem's Phlex version; if `yield`-style is required, adapt).

Add a convenience to `DG/app/components/design/views/base.rb`:
```ruby
      def shell(**opts, &block) = render Design::Views::Shell.new(**opts, &block)
```

- [ ] **Step 4: Rebuild the scoped CSS** (the new Shell adds classes):
```bash
cd /Users/mskim/Development/ruby/gems/design
bin/rails runner 'require "tailwindcss/ruby"; require Design::Engine.root.join("lib/design/tailwind_scoper"); require "fileutils"; root=Design::Engine.root; raw=root.join("tmp/design.raw.css"); out=root.join("app/assets/builds/design.css"); FileUtils.mkdir_p(raw.dirname); system(Tailwindcss::Ruby.executable.to_s, "-i", root.join("app/assets/tailwind/design.css").to_s, "-o", raw.to_s, "--minify", exception: true); File.write(out, Design::TailwindScoper.scope(File.read(raw), under: ".design-studio")); puts "rebuilt #{File.size(out)} bytes"'
```

- [ ] **Step 5: Run the tests; verify PASS** — `bin/rails test test/components/design/shell_test.rb test/design_tailwind_build_freshness_test.rb` (shell test green + CSS freshness green after the rebuild).

- [ ] **Step 6: Commit:**
```bash
git add app/components/design/views/shell.rb app/components/design/views/base.rb app/assets/builds/design.css test/components/design/shell_test.rb
git commit -m "feat(studio): Shell component (top bar + contextual sidebar), matched chrome"
```

---

## Task 4 — Re-house the 4 existing studio views in the Shell

**Files:** Modify `DG/app/components/design/views/{themes/index,themes/show,paper_sizes/edit,document_designs/edit}.rb`; rebuild `design.css`; create `DG/test/controllers/design/studio_shell_test.rb`.

- [ ] **Step 1: Write the failing integration test** `DG/test/controllers/design/studio_shell_test.rb`:
```ruby
require "test_helper"

class Design::StudioShellTest < ActionDispatch::IntegrationTest
  setup do
    @theme = Design::Theme.create!(name: "S #{SecureRandom.hex(3)}", locale: "ko")
  end

  test "themes index renders inside the shell (single top bar, no duplicate header)" do
    get design.themes_path
    assert_response :success
    assert_select "header", 1                              # the shell's single top bar
    assert_select "main"                                   # shell main region
    assert_not_includes response.body, "design-studio__header"  # old per-view header removed
  end
end
```
> Match the gem's existing integration-test setup (see `test/controllers/design/editor_locale_test.rb` for sign-in / `Design.config.locale_for` handling if the index requires it). If the index needs auth, mirror that test's approach.

- [ ] **Step 2: Run it; verify it FAILS** (old header still present / two headers).

- [ ] **Step 3: Re-house each view.** For each of `themes/index.rb`, `themes/show.rb`, `paper_sizes/edit.rb`, `document_designs/edit.rb`: replace the outer `div(class: "design-studio mx-auto max-w-* …") do … end` wrapper with a `shell(title: …, action_slot: …, action_context: …, sidebar: nil) do … end` call wrapping the **inner content only**.
  - `themes/index.rb`: **delete `header_bar`** (the Shell top bar now owns the title + home link — this is the M1 de-dup); pass `action_slot: :themes_index`; keep the themes grid as the shell body.
  - `themes/show.rb`: `action_slot: :theme_show, action_context: @theme`; keep the existing breadcrumb/content as body (sidebar comes in #1).
  - `paper_sizes/edit.rb`, `document_designs/edit.rb`: wrap their content in `shell(...)`, `sidebar: nil`, `action_slot: nil` for now (their slots come in later sub-projects).
  Keep all inner content identical — only the wrapper changes.

- [ ] **Step 4: Rebuild CSS** (re-run the Task 3 Step-4 runner) since wrapper classes changed.

- [ ] **Step 5: Run tests; verify PASS** — `bin/rails test test/controllers/design/studio_shell_test.rb test/design_tailwind_build_freshness_test.rb`, then the **full suite** `bin/rails test 2>&1 | tail -6` to confirm no regression (existing themes/index tests may assert the old `design-studio__header` or `back_to_home` link — update those assertions to the shell equivalents, FLAGGING each change as the intended de-dup, not silent breakage).

- [ ] **Step 6: Commit:**
```bash
git add app/components/design/views/themes/index.rb app/components/design/views/themes/show.rb app/components/design/views/paper_sizes/edit.rb app/components/design/views/document_designs/edit.rb app/assets/builds/design.css test/controllers/design/studio_shell_test.rb
git commit -m "feat(studio): re-house existing studio views in the Shell"
```

---

## Task 5 — book_design registers its host actions

**Files:** Modify `BD/config/initializers/design.rb`; create `BD/test/integration/studio_host_actions_test.rb`.

> book_design loads the gem via local override, so it already has the registry. Registering actions makes the host-only buttons appear on the **gem studio** pages (`/design/...`) in book_design — proving the contract end-to-end. book_write registers nothing → no buttons.

- [ ] **Step 1: Write the failing test** `BD/test/integration/studio_host_actions_test.rb`:
```ruby
require "test_helper"

class StudioHostActionsTest < ActionDispatch::IntegrationTest
  setup { @theme = Design::Theme.create!(name: "HA #{SecureRandom.hex(3)}", locale: "ko") }

  test "studio theme show page shows book_design's host actions" do
    get "/design/themes/#{@theme.id}"
    assert_response :success
    assert_includes response.body, "Export"          # registered :theme_show action
    assert_includes response.body, "Generate PDFs"
  end
end
```
> Adjust auth/locale to match book_design's existing controller tests. Confirm the exact studio route (`/design/themes/:id`) and labels.

- [ ] **Step 2: Run it; verify it FAILS** (no host actions registered → buttons absent).

- [ ] **Step 3: Register actions** in `BD/config/initializers/design.rb` (inside the existing `Design.configure do |c|` block or a `Design.config.actions` call after it). Use `main_app.*` route helpers (resolved at render time):
```ruby
  Design.config.actions.for(:theme_show) do |theme|
    [ { label: "Export",        path: main_app.export_theme_db_path(theme),     method: :post, icon: :download },
      { label: "Generate PDFs", path: main_app.generate_style_pdfs_path(theme), method: :post },
      { label: "Clone",         path: main_app.clone_theme_path(theme),         method: :post } ]
  end
  Design.config.actions.for(:themes_index) do
    [ { label: "New theme",     path: main_app.new_theme_path,        method: :get },
      { label: "Import",        path: main_app.import_themes_path,    method: :post },
      { label: "Generate",      path: main_app.generate_themes_path,  method: :post },
      { label: "Style browser", path: main_app.style_browser_path,    method: :get } ]
  end
```
> Verify each route helper exists in `BD/config/routes.rb` (`export_theme_db`, `generate_style_pdfs`, `clone` on theme member; `import`, `generate` on themes collection; `style_browser`; `new_theme`). Drop any descriptor whose route doesn't exist.

- [ ] **Step 4: Run the test; verify it PASSES.**

- [ ] **Step 5: Run book_design's suite** — `cd /Users/mskim/Development/book/book_design && bin/rails test 2>&1 | tail -8`. 0 new failures. (Do NOT run any `db:*` command — book_design holds real data; `bin/rails test` uses the test DB.)

- [ ] **Step 6: Commit** (book_design; stage only the initializer + test):
```bash
cd /Users/mskim/Development/book/book_design
git add config/initializers/design.rb test/integration/studio_host_actions_test.rb
git commit -m "feat(studio): register book_design host actions into the gem studio"
```

---

## Final verification
- [ ] `DG`: `bin/rails test` — registry/host-actions/shell/studio-shell green; CSS freshness green; 0 new failures.
- [ ] In book_design: `/design/themes` renders the new shell top bar; `/design/themes/:id` shows Export / Generate PDFs / Clone buttons (linking to host routes); the chrome visually matches book_design's `/themes` look.
- [ ] book_write unaffected (registers nothing → studio shows the shell with no host buttons; its `/design` pages still render).

## Notes / gotchas
- Blocks (not lambdas) for descriptors — `instance_exec(context, &block)` passes `context`; a lambda would raise on arity.
- Host routes need `main_app.*` (engine is `isolate_namespace`d); a bare `helpers.x_path` would hit the engine's routes.
- Rebuild `design.css` and keep `DesignTailwindBuildFreshnessTest` green whenever component classes change (Tasks 3, 4).
- `Design.config` is process-global; reset `@actions` between unit tests (Task 2 teardown) to avoid cross-test leakage.
- Match book_design's chrome by copying its exact explicit classes from `pages/themes/show.rb` + `pages/paper_sizes/show.rb`; do NOT author token CSS (keeps the studio identical to book_design's current look).
