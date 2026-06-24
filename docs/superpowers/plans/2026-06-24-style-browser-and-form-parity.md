# Style Browser + Paragraph-Style Form Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port book_design's global style browser into the `design` gem and bring the gem's paragraph-style edit form to feature-parity with book_design's, so the gem is the single source of truth (book_design can retire its versions in #6).

**Architecture:** Part A — a new `Design::StyleBrowserController#index` (`/design/style_browser`) + `Design::Views::ParagraphStyles::Browser` component, a structural port of book_design's `StyleBrowserController` + `Pages::ParagraphStyles::Index`: global, four cascading auto-submitting filters, sortable table of merged styles with override badges. The host-only per-row PDF link becomes a `:style_browser_row` host-action slot; the gem adds a per-row Edit link. Part B — add `vertical_align` (table cells) + DRY the 4 identical permit lists; an optional doc-design-level live-preview pane; styled error div. Gem-only; no migration.

**Tech Stack:** Rails engine, Phlex components, RubyUI (Card/Button/Badge), Stimulus (`design--auto-submit`, `design--live-preview`), Minitest integration tests.

**Spec:** `docs/superpowers/specs/2026-06-24-style-browser-and-form-parity-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `app/javascript/design-controllers/design/auto_submit_controller.js` | `design--auto-submit`: `submit()` → `requestSubmit()` | Create |
| `config/routes.rb` | `get "style_browser"` | Modify |
| `app/controllers/design/style_browser_controller.rb` | Cascade params + `build_style_rows` pipeline | Create |
| `app/components/design/views/paragraph_styles/browser.rb` | Filters + table (port of book_design's Index) | Create |
| `app/components/design/views/themes/index.rb` | Add a Style-browser nav link | Modify |
| `app/controllers/concerns/design/paragraph_style_params.rb` | Shared permit list incl. `vertical_align` | Create |
| `app/controllers/design/{paragraph_styles,base_paragraph_styles,theme_paragraph_styles}_controller.rb` + `concerns/design/document_design_editing.rb` | Use the shared list | Modify |
| `app/components/design/views/paragraph_styles/fields.rb` | `vertical_align` select (table cells only) | Modify |
| `app/components/design/views/paragraph_styles/form.rb` | Optional doc-design-level preview pane | Modify |
| `config/locales/{ko,en}.yml` | Browser + vertical_align keys | Modify |
| `test/controllers/design/style_browser_test.rb` | Browser controller/component | Create |
| `test/controllers/design/paragraph_styles_form_test.rb` | vertical_align + preview pane | Modify |

**Conventions (verified):**
- Use EXPLICIT slate/blue utilities, NOT book_design's dead `text-muted-foreground`/`bg-muted`/`bg-background` tokens. (book_design's `Index` uses them throughout — translate each to explicit utilities when porting.)
- `RubyUI::Card`, `RubyUI::Button(variant:)`, `RubyUI::Badge(variant:, size:)` are method-callable. There is **NO** `RubyUI::Alert`.
- Stimulus: a file at `app/javascript/design-controllers/design/<name>_controller.js` auto-registers as `design--<name>`. Reference it as `data-controller="design--auto-submit"`, action `change->design--auto-submit#submit`.
- Integration tests: `ActionDispatch::IntegrationTest`, `sign_in :david`, route helpers under `design.`. The browser is read-only but still under the studio's designer authorization (inherited from `Design::ApplicationController`).
- Route helpers (verified via `bin/rails routes`): `style_browser_path`, `edit_theme_theme_paragraph_style_path(theme, style)`, `edit_theme_paper_size_document_design_paragraph_style_path(theme, ps, dd, style)`.
- Don't commit `Gemfile.lock` (auto-bumps; stage files explicitly).

---

## PART A — Style Browser

### Task 1: `design--auto-submit` + route + browser skeleton (filters render, no rows)

**Files:**
- Create: `app/javascript/design-controllers/design/auto_submit_controller.js`
- Modify: `config/routes.rb`
- Create: `app/controllers/design/style_browser_controller.rb`
- Create: `app/components/design/views/paragraph_styles/browser.rb`
- Test: `test/controllers/design/style_browser_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Design::StyleBrowserTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Br #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "renders the browser with four cascading auto-submit filters" do
    get design.style_browser_path
    assert_response :success
    assert_select "body.design-studio"
    assert_select "form[data-controller~='design--auto-submit']"
    assert_select "select[name=?]", "theme"
    assert_select "select[name=?]", "size"
    assert_select "select[name=?]", "doc_type"
    assert_select "select[name=?]", "style_name"
    assert_select "select[data-action~='change->design--auto-submit#submit']", minimum: 4
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/controllers/design/style_browser_test.rb`
Expected: FAIL — no `style_browser_path` route.

- [ ] **Step 3: Add the route** to `config/routes.rb` (top level of `Design::Engine.routes.draw`, e.g. just before `resources :themes`):

```ruby
  get "style_browser", to: "style_browser#index", as: :style_browser
```

- [ ] **Step 4: Create the `auto-submit` controller** at `app/javascript/design-controllers/design/auto_submit_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Submits the enclosing form when a filter changes. Ported from book_design.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
```

- [ ] **Step 5: Create the controller** `app/controllers/design/style_browser_controller.rb` — full cascade loading + the (gem-portable) `build_style_rows` pipeline (rows carry OBJECTS, no `pdf_exists`):

```ruby
module Design
  class StyleBrowserController < Design::ApplicationController
    def index
      @themes = Design::Theme.all.order(:name)
      @selected_theme_name = params[:theme].presence
      @selected_theme = @selected_theme_name ? Design::Theme.find_by(name: @selected_theme_name) : nil
      @selected_theme_name = nil unless @selected_theme

      @size_names = build_size_names
      @selected_size_name = params[:size].presence
      @selected_size_name = nil unless @size_names.include?(@selected_size_name)

      @doc_types = build_doc_types
      @selected_doc_type = params[:doc_type].presence
      @selected_doc_type = nil unless @doc_types.include?(@selected_doc_type)

      @style_rows = build_style_rows
      @style_names = @style_rows.map { |r| r[:style].name }.uniq.sort
      @selected_style_name = params[:style_name].presence
      @selected_style_name = nil unless @style_names.include?(@selected_style_name)
      @style_rows = @style_rows.select { |r| r[:style].name == @selected_style_name } if @selected_style_name

      render Design::Views::ParagraphStyles::Browser.new(
        themes: @themes, size_names: @size_names, doc_types: @doc_types,
        style_names: @style_names, style_rows: @style_rows,
        selected_theme: @selected_theme_name, selected_size: @selected_size_name,
        selected_doc_type: @selected_doc_type, selected_style_name: @selected_style_name
      )
    end

    private

    def build_size_names
      scope = Design::PaperSize.all
      scope = scope.where(theme: @selected_theme) if @selected_theme
      scope.distinct.pluck(:size_name).sort
    end

    def build_doc_types
      scope = Design::DocumentDesign.joins(:paper_size)
      scope = scope.where(paper_sizes: { theme_id: @selected_theme.id }) if @selected_theme
      scope = scope.where(paper_sizes: { size_name: @selected_size_name }) if @selected_size_name
      scope.distinct.pluck(:doc_type).sort
    end

    def filtered_designs
      scope = Design::DocumentDesign.includes(:paragraph_styles, paper_size: { theme: :base_paragraph_styles })
      if @selected_theme || @selected_size_name
        scope = scope.joins(:paper_size)
        scope = scope.where(paper_sizes: { theme_id: @selected_theme.id }) if @selected_theme
        scope = scope.where(paper_sizes: { size_name: @selected_size_name }) if @selected_size_name
      end
      scope = scope.where(doc_type: @selected_doc_type) if @selected_doc_type
      scope
    end

    def build_style_rows
      designs = filtered_designs
      rows = []
      if @selected_doc_type
        designs.each do |dd|
          override_names = Set.new(dd.paragraph_styles.map(&:name))
          dd.merged_paragraph_styles.each do |style|
            rows << row_for(style, dd, override_names.include?(style.name))
          end
        end
      else
        designs.group_by { |dd| [ dd.theme.id, dd.paper_size.id ] }.each_value do |dds|
          base_added = Set.new
          dds.each do |dd|
            override_names = Set.new(dd.paragraph_styles.map(&:name))
            dd.merged_paragraph_styles.each do |style|
              if override_names.include?(style.name)
                rows << row_for(style, dd, true)
              elsif !base_added.include?(style.name)
                base_added.add(style.name)
                rows << { style: style, theme: dd.theme, paper_size: dd.paper_size, document_design: nil, doc_type: nil, is_override: false }
              end
            end
          end
        end
      end
      rows.sort_by { |r| [ r[:theme].name, r[:paper_size].size_name, r[:doc_type].to_s, r[:style].name ] }
    end

    def row_for(style, dd, is_override)
      { style: style, theme: dd.theme, paper_size: dd.paper_size, document_design: dd, doc_type: dd.doc_type, is_override: is_override }
    end
  end
end
```
> NOTE: confirm `Design::ApplicationController` has no `before_action` (e.g. `set_theme`) that requires a `:theme_id` — the browser has none. It should only inherit the studio designer-authorization. If an inherited callback breaks, report it.

- [ ] **Step 6: Create the Browser component (skeleton)** `app/components/design/views/paragraph_styles/browser.rb` — header + filters now; the table comes in Task 2. Use EXPLICIT utilities:

```ruby
module Design
  module Views
    module ParagraphStyles
      class Browser < Design::Views::Base
        def initialize(themes:, size_names:, doc_types:, style_names:, style_rows:,
                       selected_theme:, selected_size:, selected_doc_type:, selected_style_name:)
          @themes = themes
          @size_names = size_names
          @doc_types = doc_types
          @style_names = style_names
          @style_rows = style_rows
          @selected_theme = selected_theme
          @selected_size = selected_size
          @selected_doc_type = selected_doc_type
          @selected_style_name = selected_style_name
        end

        def view_template
          shell(title: I18n.t("design.style_browser.title"), action_slot: nil, sidebar: nil) do
            div(class: "mx-auto max-w-7xl px-6 py-10 flex flex-col gap-6") do
              header_section
              filters_section
              results_section
            end
          end
        end

        private

        def header_section
          div(class: "flex items-center justify-between") do
            div do
              h1(class: "text-2xl font-semibold text-slate-900") { I18n.t("design.style_browser.title") }
              p(class: "text-sm text-slate-500 mt-1") { I18n.t("design.style_browser.count", count: @style_rows.count) }
            end
            a(href: helpers.themes_path) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.style_browser.back_to_themes") } }
          end
        end

        def filters_section
          RubyUI::Card(class: "p-6") do
            form(action: helpers.style_browser_path, method: :get, data: { controller: "design--auto-submit" }) do
              div(class: "flex flex-wrap gap-4 items-end") do
                filter_select(I18n.t("design.style_browser.f_theme"), "theme", @themes.map(&:name), @selected_theme)
                filter_select(I18n.t("design.style_browser.f_size"), "size", @size_names, @selected_size)
                filter_select(I18n.t("design.style_browser.f_doc_type"), "doc_type", @doc_types, @selected_doc_type)
                filter_select(I18n.t("design.style_browser.f_style"), "style_name", @style_names, @selected_style_name)
              end
            end
          end
        end

        def filter_select(label_text, param_name, options, selected_value)
          div(class: "flex-1 min-w-[160px]") do
            label(class: "block text-sm font-medium text-slate-700 mb-1") { label_text }
            select(name: param_name, class: "w-full border border-slate-300 rounded-md px-3 py-2 text-sm bg-white",
                   data: { action: "change->design--auto-submit#submit" }) do
              option(value: "") { I18n.t("design.style_browser.all") }
              options.each do |opt|
                opt == selected_value ? option(value: opt, selected: true) { opt } : option(value: opt) { opt }
              end
            end
          end
        end

        def results_section
          RubyUI::Card(class: "p-6") do
            if @style_rows.any?
              styles_table
            else
              p(class: "text-sm text-slate-500") { I18n.t("design.style_browser.empty") }
            end
          end
        end

        # Filled in Task 2.
        def styles_table
          div { "" }
        end
      end
    end
  end
end
```

- [ ] **Step 7: Add the i18n keys** used above to `config/locales/ko.yml` + `en.yml` under a new `design.style_browser:` block — `title, count` (`"%{count} paragraph styles"` / `"문단 스타일 %{count}개"`), `back_to_themes, f_theme, f_size, f_doc_type, f_style, all, empty`. Identical keysets.

- [ ] **Step 8: Run the test**

Run: `bin/rails test test/controllers/design/style_browser_test.rb`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/design-controllers/design/auto_submit_controller.js config/routes.rb \
        app/controllers/design/style_browser_controller.rb \
        app/components/design/views/paragraph_styles/browser.rb \
        config/locales/ko.yml config/locales/en.yml test/controllers/design/style_browser_test.rb
git commit -m "feat(style_browser): controller + cascade filters skeleton"
```

---

### Task 2: The styles table (rows, override badge, swatches)

**Files:**
- Modify: `app/components/design/views/paragraph_styles/browser.rb` (replace `styles_table`)
- Test: `test/controllers/design/style_browser_test.rb`

- [ ] **Step 1: Add failing tests**

```ruby
  test "lists base styles and marks document-design overrides with a badge" do
    dd = @ps.document_designs.create!(doc_type: "chapter")
    # an override at the doc-design level
    base = @theme.base_paragraph_styles.create!(name: "body", font: "Noto", font_size: 10)
    dd.paragraph_styles.create!(name: "body", font: "Noto", font_size: 12) # override
    get design.style_browser_path(theme: @theme.name, size: @ps.size_name, doc_type: "chapter")
    assert_response :success
    assert_includes response.body, "body"          # style name shown
    assert_select "td", text: /override/i           # override marker present
  end

  test "renders a color swatch for a style with text_color" do
    dd = @ps.document_designs.create!(doc_type: "chapter")
    @theme.base_paragraph_styles.create!(name: "title", text_color: "#112233", font_size: 20)
    get design.style_browser_path(theme: @theme.name, size: @ps.size_name, doc_type: "chapter")
    assert_includes response.body, "#112233"
  end
```
> Adjust the override assertion to however the Doc-Type cell renders the override marker (a `<span>` with the localized "override" text). Keep it asserting real rendered content.

- [ ] **Step 2: Run to verify fail** — `bin/rails test test/controllers/design/style_browser_test.rb -n "/override|swatch/"` → FAIL (empty table).

- [ ] **Step 3: Replace `styles_table`** in `browser.rb` with the full table (ported from book_design's `render_styles_table`/`render_style_row`, EXPLICIT utilities, the PDF column deferred to Task 3's Actions column):

```ruby
        def styles_table
          div(class: "overflow-x-auto") do
            table(class: "w-full text-sm") do
              thead do
                tr(class: "border-b border-slate-200 text-slate-700") do
                  %w[name korean theme size doc_type font font_size color fill border actions].each do |k|
                    align = %w[font_size].include?(k) ? "text-right" : (k == "actions" ? "text-center" : "text-left")
                    th(class: "#{align} py-2 px-2 font-medium") { I18n.t("design.style_browser.col_#{k}") }
                  end
                end
              end
              tbody do
                @style_rows.each { |row| style_row(row) }
              end
            end
          end
        end

        def style_row(row)
          style = row[:style]
          tr(class: "border-b border-slate-100 hover:bg-slate-50") do
            td(class: "py-2 px-2 font-medium text-slate-900") { style.name }
            td(class: "py-2 px-2 text-slate-500") { style.korean_name.presence || "—" }
            td(class: "py-2 px-2") { row[:theme].name }
            td(class: "py-2 px-2") { row[:paper_size].size_name }
            td(class: "py-2 px-2") { doc_type_cell(row) }
            td(class: "py-2 px-2") { style.font.presence || "—" }
            td(class: "py-2 px-2 text-right") { style.font_size&.to_s || "—" }
            td(class: "py-2 px-2") { color_swatch(style.text_color) }
            td(class: "py-2 px-2") { fill_info(style) }
            td(class: "py-2 px-2") { border_info(style) }
            td(class: "py-2 px-2 text-center") { actions_cell(row) }   # filled in Task 3
          end
        end

        def doc_type_cell(row)
          if row[:doc_type].nil?
            span(class: "text-slate-400 italic") { I18n.t("design.style_browser.all_docs") }
          elsif row[:is_override]
            div(class: "flex items-center gap-1") do
              plain doc_type_label(row[:doc_type])
              RubyUI::Badge(variant: :slate, size: :sm) { I18n.t("design.style_browser.override") }
            end
          else
            plain doc_type_label(row[:doc_type])
          end
        end

        def color_swatch(color)
          return plain("—") unless color.present?
          div(class: "flex items-center gap-1") do
            span(class: "inline-block w-3 h-3 rounded-full border border-slate-300", style: "background-color: #{color}")
            span(class: "text-xs") { color }
          end
        end

        def fill_info(style)
          return plain("—") unless style.fill_type.present? && style.fill_color.present?
          div(class: "flex items-center gap-1") do
            span(class: "inline-block w-3 h-3 rounded border border-slate-300", style: "background-color: #{style.fill_color}")
            span(class: "text-xs") { style.fill_type }
          end
        end

        def border_info(style)
          return plain("—") unless style.border_thickness.present? && style.border_thickness > 0
          div(class: "flex items-center gap-1") do
            span(class: "inline-block w-3 h-3 rounded border border-slate-300", style: "background-color: #{style.border_color}") if style.border_color.present?
            span(class: "text-xs") { "#{style.border_thickness}pt" }
          end
        end

        # Filled in Task 3.
        def actions_cell(row)
          plain ""
        end
```
> `doc_type_label` is inherited from `Design::Views::Base` (added in #3). `RubyUI::Badge(variant: :slate, size: :sm)` is the **method-call** form used in `themes/index.rb:60` (no `.new`). Add the `col_*`, `all_docs`, `override` i18n keys (ko+en).

- [ ] **Step 4: Run** — `bin/rails test test/controllers/design/style_browser_test.rb` → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/design/views/paragraph_styles/browser.rb config/locales/ko.yml config/locales/en.yml test/controllers/design/style_browser_test.rb
git commit -m "feat(style_browser): styles table with override badge + swatches"
```

---

### Task 3: Per-row Edit link + `:style_browser_row` host-action slot

**Files:**
- Modify: `app/components/design/views/paragraph_styles/browser.rb` (`actions_cell`)
- Test: `test/controllers/design/style_browser_test.rb`

- [ ] **Step 1: Add failing tests**

```ruby
  test "base row Edit link points at the theme-level style edit; override row at the doc-design level" do
    dd = @ps.document_designs.create!(doc_type: "chapter")
    base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    ovr_dd = @ps.document_designs.create!(doc_type: "toc")
    ovr_dd.paragraph_styles.create!(name: "body", font_size: 12)
    get design.style_browser_path # all-doc-types view → base rows + override rows
    # base "body" row → theme-level edit
    assert_select "a[href=?]", design.edit_theme_theme_paragraph_style_path(@theme, base)
    # override row → doc-design-level edit
    ovr = ovr_dd.paragraph_styles.find_by(name: "body")
    assert_select "a[href=?]", design.edit_theme_paper_size_document_design_paragraph_style_path(@theme, @ps, ovr_dd, ovr)
  end

  test "renders a registered host action in the per-row slot" do
    Design.config.actions.for(:style_browser_row) { |row| [ { label: "PDF", path: "/x.pdf" } ] }
    @ps.document_designs.create!(doc_type: "chapter")
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    get design.style_browser_path
    assert_select "a[href='/x.pdf']", text: "PDF"
  ensure
    Design.config.actions.for(:style_browser_row) { nil }   # reset (registrations is private)
  end
```
> `Design.config.actions.registrations` is PRIVATE (`action_registry.rb:12`), so reset the slot by re-registering a `nil`-returning block (`for(:slot) { nil }` → `resolve` returns the block, `render_host_actions` instance_execs it → `Array(nil)` → renders nothing). Keep the test hermetic.

- [ ] **Step 2: Run to verify fail** — `-n "/Edit link|host action/"` → FAIL.

- [ ] **Step 3: Implement `actions_cell`** in `browser.rb`:

```ruby
        def actions_cell(row)
          div(class: "flex items-center justify-center gap-2") do
            if (path = edit_path_for(row))
              a(href: path, class: "text-xs text-blue-600 hover:underline") { I18n.t("design.shared.edit") }
            end
            render_host_actions(:style_browser_row, row)
          end
        end

        # Override rows edit at the doc-design level; base rows are theme-level
        # (merged_paragraph_styles only yields theme-base + overrides — see spec Decision 4).
        def edit_path_for(row)
          style = row[:style]
          if row[:is_override] && row[:document_design]
            helpers.edit_theme_paper_size_document_design_paragraph_style_path(row[:theme], row[:paper_size], row[:document_design], style)
          elsif style.styleable.is_a?(Design::Theme)
            helpers.edit_theme_theme_paragraph_style_path(row[:theme], style)
          end
        end
```
> `render_host_actions` (from `Base`, used in #1/#2) renders the registered descriptors with the row as context; renders nothing if no block is registered. Reuse `design.shared.edit` (exists).

- [ ] **Step 4: Run** — `bin/rails test test/controllers/design/style_browser_test.rb` → PASS (all browser tests).

- [ ] **Step 5: Commit**

```bash
git add app/components/design/views/paragraph_styles/browser.rb test/controllers/design/style_browser_test.rb
git commit -m "feat(style_browser): per-row Edit link + :style_browser_row host slot"
```

---

### Task 4: Entry point on the themes index

**Files:**
- Modify: `app/components/design/views/themes/index.rb`
- Test: `test/controllers/design/themes_index_flat_test.rb` (existing index test — add an assertion)

- [ ] **Step 1: Add a failing test** (to the themes-index test that renders `/design/themes`; mirror its setup):

```ruby
  test "themes index links to the style browser" do
    get design.themes_path
    assert_response :success
    assert_select "a[href=?]", design.style_browser_path
  end
```

- [ ] **Step 2: Run to verify fail** → FAIL (no link).

- [ ] **Step 3: Add the link** in `themes/index.rb` — read the component's header area first, then add (near the "New theme" / host-actions area):

```ruby
          a(href: helpers.style_browser_path, class: "text-sm font-medium text-blue-600 hover:underline") { I18n.t("design.style_browser.nav_link") }
```
Add `design.style_browser.nav_link` ("Style browser" / "스타일 브라우저") to ko+en.

- [ ] **Step 4: Run** the index test → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/design/views/themes/index.rb config/locales/ko.yml config/locales/en.yml <the test file>
git commit -m "feat(style_browser): link from themes index"
```

---

## PART B — Form Parity

### Task 5: `vertical_align` field (table cells) + DRY the permit lists

The four `paragraph_style_params` permit lists are byte-for-byte identical (verified). Extract one shared list and add `:vertical_align`.

**Files:**
- Create: `app/controllers/concerns/design/paragraph_style_params.rb`
- Modify: the 3 level controllers + `concerns/design/document_design_editing.rb`
- Modify: `app/components/design/views/paragraph_styles/fields.rb`
- Test: `test/controllers/design/paragraph_styles_form_test.rb`, `test/components/design/paragraph_fields_test.rb`

- [ ] **Step 1: Add failing tests**

Controller round-trip (in `paragraph_styles_form_test.rb`, doc-design level — mirror its existing setup):
```ruby
  test "updating a table cell style persists vertical_align" do
    # build a table_body_cell style at the doc-design level (mirror existing test setup for @theme/@ps/@dd)
    style = @dd.paragraph_styles.create!(name: "table_body_cell", font_size: 9)
    patch design.theme_paper_size_document_design_paragraph_style_path(@theme, @ps, @dd, style),
          params: { paragraph_style: { vertical_align: "middle" } }
    assert_response :redirect
    assert_equal "middle", style.reload.vertical_align
  end
```
Fields component (in `paragraph_fields_test.rb`): the `vertical_align` select renders for a `table_body_cell` style and is absent for a `body` style.

- [ ] **Step 2: Run to verify fail** → FAIL (param stripped / field absent).

- [ ] **Step 3: Create the shared concern** `app/controllers/concerns/design/paragraph_style_params.rb`:

```ruby
module Design
  module ParagraphStyleParams
    extend ActiveSupport::Concern

    PERMITTED = %i[
      name korean_name font font_size scale
      text_color text_align tracking space_width text_line_spacing
      first_line_indent left_indent right_indent
      space_before space_after space_before_in_lines space_after_in_lines
      bold_font bold_text_color emphasis_font emphasis_color
      fill_type fill_color fill_ending_color fill_gradient_direction
      border_thickness border_color border_side rounded_corners corner_radius
      padding_top padding_bottom
      vertical_align
    ].freeze

    private

    def paragraph_style_params
      params.require(:paragraph_style).permit(*PERMITTED)
    end
  end
end
```

- [ ] **Step 4: Use it** — in each of `paragraph_styles_controller.rb`, `base_paragraph_styles_controller.rb`, `theme_paragraph_styles_controller.rb`, and `concerns/design/document_design_editing.rb`: `include Design::ParagraphStyleParams` and DELETE the local `paragraph_style_params` definition. (For `document_design_editing.rb`, which is itself a concern, include the params concern or just reference `Design::ParagraphStyleParams::PERMITTED` — pick whichever keeps a single source; if a controller includes both concerns, ensure no duplicate-method warning.)

- [ ] **Step 5: Add the `vertical_align` select to `Fields`** — read `fields.rb` to find an appropriate section, then add a select rendered only for table cells:

```ruby
        # within the appropriate section's block:
        if @paragraph_style.name.in?(%w[table_heading_cell table_body_cell])
          select_field(I18n.t("design.fields.vertical_align"), :vertical_align,
                       Design::ParagraphStyle::VERTICAL_ALIGNS)
        end
```
Use whatever the component's existing select helper is named (read the file). Add `design.fields.vertical_align` + option labels (or use the raw `top/middle/bottom` values) to ko+en.

- [ ] **Step 6: Run** the form + fields tests → PASS. Then the whole paragraph-style suite:

Run: `bin/rails test test/controllers/design/paragraph_styles_form_test.rb test/components/design/paragraph_fields_test.rb test/components/design/paragraph_style_panel_test.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/concerns/design/paragraph_style_params.rb \
        app/controllers/design/paragraph_styles_controller.rb \
        app/controllers/design/base_paragraph_styles_controller.rb \
        app/controllers/design/theme_paragraph_styles_controller.rb \
        app/controllers/concerns/design/document_design_editing.rb \
        app/components/design/views/paragraph_styles/fields.rb \
        config/locales/ko.yml config/locales/en.yml \
        test/controllers/design/paragraph_styles_form_test.rb test/components/design/paragraph_fields_test.rb
git commit -m "feat(paragraph_styles): vertical_align for table cells + DRY permit list"
```

---

### Task 6: Optional doc-design-level live-preview pane

book_design's style form shows a live JPG preview beside the form. Add it to the gem's doc-design-level paragraph-style `Form` only (the level bound to one `DocumentDesign`).

**Files:**
- Modify: `app/components/design/views/paragraph_styles/form.rb`
- Test: `test/controllers/design/paragraph_styles_form_test.rb`

- [ ] **Step 1: Read `form.rb`** — its current signature is `Form.new(paragraph_style:, form_url:, cancel_url:, crumbs:)` (no context objects). It does NOT receive `document_design`/`paper_size`/`theme`. So the preview pane needs a small threading change: add optional `document_design: nil, paper_size: nil, theme: nil` keyword args to `Form#initialize`, render the preview frame only when `@document_design` is present, and update the **3 render call sites** — `ParagraphStylesController#edit` (doc-design level, pass the real objects) and `theme_paragraph_styles_controller`/`base_paragraph_styles_controller` (pass nothing → defaults to nil → no pane). Find the exact call sites with `grep -rn "ParagraphStyles::Form.new" app/`.

- [ ] **Step 2: Add a failing test**

```ruby
  test "doc-design-level style form renders a live preview frame; theme-level does not" do
    style = @dd.paragraph_styles.create!(name: "body", font_size: 10)
    get design.edit_theme_paper_size_document_design_paragraph_style_path(@theme, @ps, @dd, style)
    assert_response :success
    assert_select "turbo-frame#preview_frame"
    # theme-level: no preview frame
    tstyle = @theme.base_paragraph_styles.create!(name: "body2", font_size: 10)
    get design.edit_theme_theme_paragraph_style_path(@theme, tstyle)
    assert_response :success
    assert_select "turbo-frame#preview_frame", count: 0
  end
```

- [ ] **Step 3: Implement the pane** — render the preview turbo-frame (reuse the `DocumentDesigns` preview src: `helpers.preview_theme_paper_size_document_design_path(theme, ps, dd)`, `loading: "lazy"`, the existing `design--live-preview` wiring) in `form.rb` ONLY when the style is doc-design-level (i.e. the form has a `document_design`). If the component doesn't receive `document_design`/`paper_size` today, thread them in from the doc-design-level controller/render path (`paragraph_styles_controller#edit`) and leave the theme/paper-size render paths passing `nil` (no pane). Keep the change minimal and gated; if threading the context turns out to be a larger refactor than expected, STOP and report DONE_WITH_CONCERNS with what you found (we may split this into its own task).

- [ ] **Step 4: Run** — `bin/rails test test/controllers/design/paragraph_styles_form_test.rb` → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/design/views/paragraph_styles/form.rb app/controllers/design/paragraph_styles_controller.rb test/controllers/design/paragraph_styles_form_test.rb
git commit -m "feat(paragraph_styles): live-preview pane on doc-design-level style form"
```

---

### Task 7: Full suite + freshness + rubocop + push

- [ ] **Step 1: Full suite** — `bin/rails test` → 0 failures/errors. Watch i18n parity + the themes-index + paragraph-style suites.

- [ ] **Step 2: Tailwind freshness** — the browser added table/swatch utilities. If `test/design_tailwind_build_freshness_test.rb` fails, rebuild (same recipe as prior sub-projects) and commit `app/assets/builds/design.css`:

```bash
bin/rails runner 'require Design::Engine.root.join("lib/design/tailwind_scoper"); require "tailwindcss/ruby"; require "tmpdir"; \
  exe = Tailwindcss::Ruby.executable.to_s; root = Design::Engine.root; \
  Dir.mktmpdir { |d| raw = File.join(d,"raw.css"); system(exe, "-i", root.join("app/assets/tailwind/design.css").to_s, "-o", raw, "--minify", exception: true); \
  File.write(root.join("app/assets/builds/design.css"), Design::TailwindScoper.scope(File.read(raw), under: ".design-studio")) }'
bin/rails test test/design_tailwind_build_freshness_test.rb
git add app/assets/builds/design.css && git commit -m "chore(design): rebuild design.css for style-browser utilities"
```

- [ ] **Step 3: Rubocop** (omakase config):

```bash
bundle exec rubocop --config "$(bundle show rubocop-rails-omakase)/rubocop.yml" \
  app/controllers/design/style_browser_controller.rb \
  app/components/design/views/paragraph_styles/browser.rb \
  app/controllers/concerns/design/paragraph_style_params.rb
```
Expected: clean, or offenses consistent with surrounding style.

- [ ] **Step 4: Manual smoke (optional)** — open `/design/style_browser`, change filters (auto-submits), verify rows/badges/swatches, click a row Edit link, edit a `table_body_cell` style's vertical_align, open a doc-design-level style edit (preview pane shows).

- [ ] **Step 5: Push** — `git push origin main`.

---

## Notes for the implementer

- **No migration.** `vertical_align` is an existing validated column; the browser is read-only.
- **Translate book_design's dead tokens.** The ported `Index` is full of `text-muted-foreground`, `bg-muted`, `bg-background`, `hover:bg-muted/50` — replace each with explicit slate utilities (the plan's code already does). Never emit the token classes.
- **Host slot is the compatibility seam:** the gem renders no PDF link; book_design will register `:style_browser_row` to supply it (and book_write registers nothing). This is how the gem stays the single source of truth without absorbing host-only PDF export.
- **`merged_paragraph_styles` yields theme-base + doc-design overrides only** — base rows are always theme-level (spec Decision 4); there's no paper-size-level base row, so no `base_paragraph_styles` edit branch.
- **Sequence A before B** so routes/components exist; Task 6 (preview pane) is the riskiest — if threading `document_design` into the style `Form` is bigger than a small change, stop and report.
