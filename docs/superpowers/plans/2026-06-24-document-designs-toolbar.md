# Document-Designs Editor Toolbar + Doc-Type Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toolbar with a clickable theme/paper-size breadcrumb and a doc-type **dropdown switcher** to the gem's document-design editor, so you can jump to a sibling doc design without leaving the editor.

**Architecture:** A new Phlex `Design::Views::DocumentDesigns::EditorToolbar` replaces the static breadcrumb at the top of `Edit`. The dropdown is a verbatim port of book_design's `dropdown_controller.js`, dropped into the gem's auto-loaded Stimulus dir as `design--dropdown`. The switcher lists the paper size's **interior** doc designs **in reading order** (cover panels excluded), via a new `DocumentDesign.interior_for(paper_size)` shared with `themes_controller`. Doc-type labels reuse the gem's i18n `doc_type_label`, promoted to `Design::Views::Base`. Gem-only; no migration.

**Tech Stack:** Rails engine, Phlex components, Stimulus (auto-loaded via `eagerLoadControllersFrom`), Minitest integration tests, RubyUI (none new here).

**Spec:** `docs/superpowers/specs/2026-06-24-document-designs-toolbar-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `app/models/design/document_design.rb` | Add `self.interior_for(paper_size)` (reading-ordered, cover-panels excluded) | Modify |
| `app/controllers/design/themes_controller.rb` | `interior_document_designs` delegates to `DocumentDesign.interior_for` | Modify |
| `app/components/design/views/base.rb` | Host `doc_type_label(doc_type)` for all views | Modify |
| `app/components/design/views/themes/show.rb` | Drop the local `doc_type_label`; update its one call site | Modify |
| `app/components/design/views/document_designs/editor_toolbar.rb` | The toolbar: breadcrumb links + doc-type dropdown | Create |
| `app/components/design/views/document_designs/edit.rb` | Replace `Breadcrumb` with `EditorToolbar` | Modify |
| `app/javascript/design-controllers/design/dropdown_controller.js` | `design--dropdown`: toggle + outside-click close | Create |
| `config/locales/{ko,en}.yml` | `design.document_designs.switch_doc_type` (button aria/title) | Modify |
| `test/models/design/document_design_interior_for_test.rb` | Cover `interior_for` | Create |
| `test/controllers/design/document_designs_edit_test.rb` | Toolbar + switcher rendering | Modify |

**Conventions (verified in-repo):**
- View components subclass `Design::Views::Base`; it already mixes in `Phlex::Rails::Helpers::Routes` + `RubyUI` and provides `design_preview_img`, `action_button_class`. Route helpers are reached via `helpers.*_path`.
- The studio chrome uses **explicit** slate/blue Tailwind utilities (e.g. `text-slate-500 hover:text-slate-900`, `text-blue-600`), NOT book_design's dead `text-muted-foreground`/`text-foreground` tokens.
- Integration tests: `ActionDispatch::IntegrationTest`, `sign_in :david`, owned theme (`user_id: users(:david).id`) so it's editable, `assert_select`, route helpers under `design.`.
- Stimulus: any file at `app/javascript/design-controllers/design/<name>_controller.js` auto-registers as `design--<name>` (via `eagerLoadControllersFrom("design-controllers", …)` in `app/javascript/design/index.js`). No manual registration.
- Don't commit `Gemfile.lock` (it auto-bumps from a sibling checkout; stage specific files).

---

### Task 1: `DocumentDesign.interior_for` + DRY `themes_controller`

**Files:**
- Modify: `app/models/design/document_design.rb`
- Modify: `app/controllers/design/themes_controller.rb:77-81`
- Test: `test/models/design/document_design_interior_for_test.rb`

- [ ] **Step 1: Write the failing test**

`test/models/design/document_design_interior_for_test.rb`:
```ruby
require "test_helper"

class Design::DocumentDesignInteriorForTest < ActiveSupport::TestCase
  setup do
    # Unowned (system) theme is fine for a pure model query test — no auth involved.
    @theme = Design::Theme.create!(name: "IF #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "returns interior designs in reading order, excluding cover panels" do
    # Create out of reading order; include a cover panel that must be excluded.
    epilogue = @ps.document_designs.create!(doc_type: "epilogue")
    chapter  = @ps.document_designs.create!(doc_type: "chapter")
    title    = @ps.document_designs.create!(doc_type: "title_page")
    @ps.document_designs.create!(doc_type: "front_page") # cover panel

    result = Design::DocumentDesign.interior_for(@ps)

    assert_equal [ title, chapter, epilogue ], result
    assert_not_includes result.map(&:doc_type), "front_page"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/models/design/document_design_interior_for_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'interior_for'`.

- [ ] **Step 3: Add the class method** to `app/models/design/document_design.rb` (next to `by_reading_order`, ~line 38):

```ruby
    def self.interior_for(paper_size)
      by_reading_order(paper_size.document_designs.where.not(doc_type: COVER_PANEL_TYPES))
    end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/models/design/document_design_interior_for_test.rb`
Expected: PASS.

- [ ] **Step 5: DRY the controller** — rewrite `themes_controller.rb:77-81`'s `interior_document_designs` to delegate:

```ruby
    def interior_document_designs(paper_size)
      Design::DocumentDesign.interior_for(paper_size)
    end
```

- [ ] **Step 6: Confirm no regression** — the theme-show grid is unchanged:

Run: `bin/rails test test/controllers/design/themes_show_grouped_test.rb test/controllers/design/themes_show_editable_chips_test.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/models/design/document_design.rb app/controllers/design/themes_controller.rb test/models/design/document_design_interior_for_test.rb
git commit -m "feat(document_designs): DocumentDesign.interior_for + DRY themes_controller"
```

---

### Task 2: Promote `doc_type_label` to `Design::Views::Base`

A refactor (no behavior change). `doc_type_label` is currently a private method in `themes/show.rb` taking a `dd`; the toolbar needs it too. Move it to `Base`, change its arg to the `doc_type` string, and update the single call site. Existing theme-show tests (which assert doc-type labels render) are the safety net.

**Files:**
- Modify: `app/components/design/views/base.rb`
- Modify: `app/components/design/views/themes/show.rb` (call site `:133`, remove local def `:165-167`)

- [ ] **Step 1: Add `doc_type_label` to `Base`** — in `app/components/design/views/base.rb`, add a public method (e.g. after `action_button_class`):

```ruby
      # Localized label for a doc_type (falls back to the raw key for unmapped types).
      def doc_type_label(doc_type) = I18n.t("design.doc_types.#{doc_type}", default: doc_type)
```

- [ ] **Step 2: Update the show.rb call site** — change `themes/show.rb:133` from:

```ruby
          label = doc_type_label(dd)
```
to:
```ruby
          label = doc_type_label(dd.doc_type)
```

- [ ] **Step 3: Remove the now-duplicate local method** — delete the private `def doc_type_label(dd) … end` (`themes/show.rb:165-167`).

- [ ] **Step 4: Verify no behavior change** — existing tests that render doc-type labels stay green:

Run: `bin/rails test test/controllers/design/themes_show_grouped_test.rb test/components/design/localization_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/design/views/base.rb app/components/design/views/themes/show.rb
git commit -m "refactor(views): promote doc_type_label to Views::Base (shared by toolbar)"
```

---

### Task 3: `EditorToolbar` component + `design--dropdown` controller, wired into `Edit`

**Files:**
- Create: `app/components/design/views/document_designs/editor_toolbar.rb`
- Create: `app/javascript/design-controllers/design/dropdown_controller.js`
- Modify: `app/components/design/views/document_designs/edit.rb:18-22`
- Modify: `config/locales/ko.yml`, `config/locales/en.yml`
- Test: `test/controllers/design/document_designs_edit_test.rb`

- [ ] **Step 1: Add the i18n key** (button aria/title) under `design.document_designs:` in **both** locale files. ko.yml:
```yaml
      switch_doc_type: "문서 유형 전환"
```
en.yml:
```yaml
      switch_doc_type: "Switch document type"
```
(Verify the `design.document_designs:` block exists in each; add the key at that level. Keep keysets identical.)

- [ ] **Step 2: Write the failing tests** — add to `test/controllers/design/document_designs_edit_test.rb`:

```ruby
  test "edit renders the editor toolbar with clickable theme and paper-size links" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "a[href=?]", design.theme_path(@theme)
    assert_select "a[href=?]", design.edit_theme_paper_size_path(@theme, @ps)
  end

  test "edit renders the doc-type dropdown wired to design--dropdown" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_select "[data-controller~='design--dropdown']"
    assert_select "[data-design--dropdown-target='menu']"
  end

  test "doc-type switcher lists interior siblings in reading order, excludes cover panels, marks current" do
    title    = @ps.document_designs.create!(doc_type: "title_page")
    epilogue = @ps.document_designs.create!(doc_type: "epilogue")
    cover    = @ps.document_designs.create!(doc_type: "front_page") # must be excluded
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd) # @dd = chapter
    body = response.body

    title_path    = design.edit_theme_paper_size_document_design_path(@theme, @ps, title)
    chapter_path  = design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    epilogue_path = design.edit_theme_paper_size_document_design_path(@theme, @ps, epilogue)
    cover_path    = design.edit_theme_paper_size_document_design_path(@theme, @ps, cover)

    # reading order: title_page (front) < chapter (body) < epilogue (rear)
    assert body.index(title_path) < body.index(chapter_path), "title_page before chapter"
    assert body.index(chapter_path) < body.index(epilogue_path), "chapter before epilogue"
    # cover panel excluded from the switcher
    assert_select "a[href=?]", cover_path, count: 0
    # current doc design highlighted
    assert_select "a.bg-blue-50[href=?]", chapter_path
  end
```

- [ ] **Step 3: Run to verify they fail**

Run: `bin/rails test test/controllers/design/document_designs_edit_test.rb -n "/toolbar|dropdown|switcher/"`
Expected: FAIL — no toolbar/dropdown in the rendered page yet.

- [ ] **Step 4: Create the dropdown Stimulus controller** at `app/javascript/design-controllers/design/dropdown_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Toggles a dropdown menu; closes on outside click. Ported from book_design.
export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    this.menuTarget.classList.toggle("hidden")
  }

  connect() {
    this.outsideClickHandler = (event) => {
      if (!this.element.contains(event.target)) {
        this.menuTarget.classList.add("hidden")
      }
    }
    document.addEventListener("click", this.outsideClickHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.outsideClickHandler)
  }
}
```

- [ ] **Step 5: Create the `EditorToolbar` component** at `app/components/design/views/document_designs/editor_toolbar.rb`:

```ruby
module Design
  module Views
    module DocumentDesigns
      class EditorToolbar < Design::Views::Base
        def initialize(theme:, paper_size:, document_design:)
          @theme = theme
          @paper_size = paper_size
          @document_design = document_design
        end

        def view_template
          div(class: "flex items-center gap-1.5 text-sm") do
            a(href: helpers.theme_path(@theme),
              class: "text-slate-500 hover:text-slate-900") { @theme.name }
            span(class: "text-slate-400") { "/" }
            a(href: helpers.edit_theme_paper_size_path(@theme, @paper_size),
              class: "text-slate-500 hover:text-slate-900") { @paper_size.display_name }
            span(class: "text-slate-400") { "/" }
            doc_type_dropdown
          end
        end

        private

        def doc_type_dropdown
          div(class: "relative inline-block", data: { controller: "design--dropdown" }) do
            button(
              type: "button",
              title: I18n.t("design.document_designs.switch_doc_type"),
              class: "font-medium text-slate-900 hover:text-blue-600 flex items-center gap-1",
              data: { action: "design--dropdown#toggle" }
            ) do
              plain doc_type_label(@document_design.doc_type)
              span(class: "text-xs") { "▾" }
            end

            div(
              class: "hidden absolute left-0 top-full mt-1 bg-white border border-slate-200 rounded-md shadow-lg py-1 z-50 min-w-[180px]",
              data: { "design--dropdown-target": "menu" }
            ) do
              Design::DocumentDesign.interior_for(@paper_size).each do |dd|
                current = dd.id == @document_design.id
                a(
                  href: helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, dd),
                  class: "block px-3 py-1.5 text-sm #{current ? "bg-blue-50 text-blue-700 font-medium" : "text-slate-700 hover:bg-slate-50"}"
                ) { plain doc_type_label(dd.doc_type) }
              end
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 6: Wire it into `Edit`** — in `app/components/design/views/document_designs/edit.rb`, replace the `render Design::Views::Breadcrumb.new(crumbs: […])` call (lines 18-22) with:

```ruby
              render Design::Views::DocumentDesigns::EditorToolbar.new(
                theme: @theme, paper_size: @paper_size, document_design: @document_design
              )
```
Leave the `h1` and everything below unchanged.

- [ ] **Step 7: Run the new tests**

Run: `bin/rails test test/controllers/design/document_designs_edit_test.rb`
Expected: PASS (new toolbar/switcher tests + all pre-existing edit tests).

- [ ] **Step 8: Commit**

```bash
git add app/components/design/views/document_designs/editor_toolbar.rb \
        app/javascript/design-controllers/design/dropdown_controller.js \
        app/components/design/views/document_designs/edit.rb \
        config/locales/ko.yml config/locales/en.yml \
        test/controllers/design/document_designs_edit_test.rb
git commit -m "feat(document_designs): editor toolbar + doc-type dropdown switcher"
```

---

### Task 4: Full-suite green + rubocop + push

- [ ] **Step 1: Full suite**

Run: `bin/rails test`
Expected: PASS (0 failures, 0 errors). Watch the i18n parity test and the theme-show + localization tests.

- [ ] **Step 2: Tailwind freshness** — the toolbar uses only utilities already present elsewhere (slate/blue, `absolute`, `shadow-lg`, `min-w-[180px]`, `z-50`). If `test/design_tailwind_build_freshness_test.rb` fails, rebuild the CSS the way that test does and commit it:

```bash
bin/rails runner 'require Design::Engine.root.join("lib/design/tailwind_scoper"); require "tailwindcss/ruby"; require "tmpdir"; \
  exe = Tailwindcss::Ruby.executable.to_s; root = Design::Engine.root; \
  Dir.mktmpdir { |d| raw = File.join(d,"raw.css"); system(exe, "-i", root.join("app/assets/tailwind/design.css").to_s, "-o", raw, "--minify", exception: true); \
  File.write(root.join("app/assets/builds/design.css"), Design::TailwindScoper.scope(File.read(raw), under: ".design-studio")) }'
bin/rails test test/design_tailwind_build_freshness_test.rb
git add app/assets/builds/design.css && git commit -m "chore(design): rebuild design.css for toolbar utilities"
```
(Only if it failed; otherwise skip.)

- [ ] **Step 3: Rubocop** (omakase config — bare `rubocop` runs default rules the gem doesn't enforce; lint against the actual config):

```bash
bundle exec rubocop --config "$(bundle show rubocop-rails-omakase)/rubocop.yml" \
  app/components/design/views/document_designs/editor_toolbar.rb \
  app/models/design/document_design.rb app/components/design/views/base.rb
```
Expected: clean, or offenses consistent with the surrounding code's existing style (don't churn the codebase to satisfy cops it doesn't already obey).

- [ ] **Step 4: Manual smoke (optional)** — in book_write/dummy, open a doc-design editor, click the doc-type button → menu opens, click a sibling → navigates to its editor; click outside → menu closes. Confirm cover-panel types aren't listed.

- [ ] **Step 5: Push**

```bash
git push origin main
```

---

## Notes for the implementer

- **No migration, no model schema change.** `interior_for` is a pure query method.
- **Stimulus namespace is load-bearing:** the file MUST be `app/javascript/design-controllers/design/dropdown_controller.js` so it registers as `design--dropdown` (matching the `data-controller`/`data-action`/`data-…-target` the toolbar emits). Don't rename.
- **`doc_type_label` lives on `Base` now** (Task 2) — the toolbar calls it directly (inherited). Don't redefine it locally.
- **Switcher excludes cover panels** by construction (`interior_for`); the test asserts this. This is a deliberate divergence from book_design (which lists all doc_types) — see spec Decision 3.
- **Paper-size link** goes to `edit_theme_paper_size_path` (the gem has no per-size show), matching the editor's prior breadcrumb.
- The toolbar is rendered first in the edit body, so sibling edit-paths first appear in the dropdown — the reading-order `body.index` assertions are stable.
