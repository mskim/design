# Paragraph-Style Save Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "scope" checkbox next to Save in the document-design paragraph-style panel so an edit defaults to "this document type, all paper sizes" and can opt into "all document types."

**Architecture:** No migration. The default scope fans out document-level overrides onto every same-doc_type `DocumentDesign` across paper sizes; the opt-in writes the theme base and clears same-name overrides theme-wide. Logic lives in three `Theme` methods; `panel_update` dispatches on a non-model `apply_scope` param; the Panel renders the checkbox and a confirm-guard Stimulus controller.

**Tech Stack:** Rails 8.1 engine, Phlex views, Stimulus (importmap, `eagerLoadControllersFrom`), Minitest. Spec: `docs/superpowers/specs/2026-06-28-paragraph-style-save-scope-design.md`.

**Scope note / known limitation:** This panel path stops persisting *name* changes to an existing style (the override key is the persisted `style.name`; attrs are written with `.except(:name)` so names never diverge across siblings). Renaming an existing style via this panel was incidental and is out of scope; new-style creation (a different controller action, `create`) is unaffected.

All paths below are relative to the `design` gem root: `/Users/mskim/Development/ruby/gems/design`.

---

### Task 1: Theme — fan-out, all, and shadow-count methods

**Files:**
- Modify: `app/models/design/theme.rb`
- Test: `test/models/design/theme_test.rb`

- [ ] **Step 1: Write failing tests**

Append to `test/models/design/theme_test.rb` (inside the class):

```ruby
test "apply_paragraph_style_to_doc_type! writes an override to every same-doc_type design and leaves base + other doc_types alone" do
  theme = Design::Theme.create!(name: "FT #{SecureRandom.hex(3)}", locale: "ko")
  s1 = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  s2 = theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
  ch1 = s1.document_designs.create!(doc_type: "chapter")
  ch2 = s2.document_designs.create!(doc_type: "chapter")
  poem = s1.document_designs.create!(doc_type: "poem")
  theme.base_paragraph_styles.create!(name: "body", font_size: 10)

  theme.apply_paragraph_style_to_doc_type!("chapter", "body", { "font_size" => "13" })

  assert_equal "13.0", ch1.paragraph_styles.find_by(name: "body").font_size.to_s
  assert_equal "13.0", ch2.paragraph_styles.find_by(name: "body").font_size.to_s
  assert_nil poem.paragraph_styles.find_by(name: "body"), "other doc_types untouched"
  assert_equal 10, theme.base_paragraph_styles.find_by(name: "body").font_size, "base untouched"
end

test "apply_paragraph_style_to_doc_type! is idempotent (upsert, no duplicate rows)" do
  theme = Design::Theme.create!(name: "FT #{SecureRandom.hex(3)}", locale: "ko")
  s1 = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  ch1 = s1.document_designs.create!(doc_type: "chapter")
  theme.apply_paragraph_style_to_doc_type!("chapter", "body", { "font_size" => "13" })
  theme.apply_paragraph_style_to_doc_type!("chapter", "body", { "font_size" => "15" })
  assert_equal 1, ch1.paragraph_styles.where(name: "body").count
  assert_equal "15.0", ch1.paragraph_styles.find_by(name: "body").font_size.to_s
end

test "apply_paragraph_style_to_all! upserts the base (creating it when absent) and clears same-name overrides theme-wide" do
  theme = Design::Theme.create!(name: "FA #{SecureRandom.hex(3)}", locale: "ko")
  s1 = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  ch1 = s1.document_designs.create!(doc_type: "chapter")
  poem = s1.document_designs.create!(doc_type: "poem")
  ch1.paragraph_styles.create!(name: "wing_left", font_size: 8)   # override-only style, no base row
  poem.paragraph_styles.create!(name: "wing_left", font_size: 9)

  theme.apply_paragraph_style_to_all!("wing_left", { "font_size" => "20" })

  base = theme.base_paragraph_styles.find_by(name: "wing_left")
  assert_not_nil base, "base row created when none existed"
  assert_equal "20.0", base.font_size.to_s
  assert_equal 0, ch1.paragraph_styles.where(name: "wing_left").count, "shadowing overrides cleared"
  assert_equal 0, poem.paragraph_styles.where(name: "wing_left").count
end

test "shadow_override_doc_types returns distinct doc_types (one per doc_type, not per row)" do
  theme = Design::Theme.create!(name: "SH #{SecureRandom.hex(3)}", locale: "ko")
  s1 = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  s2 = theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
  s1.document_designs.create!(doc_type: "chapter").paragraph_styles.create!(name: "body")
  s2.document_designs.create!(doc_type: "chapter").paragraph_styles.create!(name: "body")
  s1.document_designs.create!(doc_type: "poem").paragraph_styles.create!(name: "body")

  result = theme.shadow_override_doc_types("body")
  assert_equal %w[chapter poem], result.sort
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rails test test/models/design/theme_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'apply_paragraph_style_to_doc_type!'`.

- [ ] **Step 3: Implement**

In `app/models/design/theme.rb`, add public methods (after `default_paper_size`, before `private`):

```ruby
# Write `attrs` (a permitted paragraph-style params hash) as a document-level
# override of `name` onto every DocumentDesign of `doc_type` across this theme's
# paper sizes (the current document is one of them). The theme base is untouched;
# because all sizes share one base, identical override attrs resolve identically.
def apply_paragraph_style_to_doc_type!(doc_type, name, attrs)
  document_designs.where(doc_type: doc_type).find_each do |dd|
    dd.upsert_paragraph_style!(name, attrs)
  end
end

# Write `attrs` to the theme base style `name` (creating the base row if a style
# of that name exists only as a document override), then destroy every same-name
# per-doc_type override across the theme so the base value shows everywhere.
def apply_paragraph_style_to_all!(name, attrs)
  base = base_paragraph_styles.find_or_initialize_by(name: name)
  base.update!(attrs.except(:name))
  document_designs.find_each do |dd|
    dd.paragraph_styles.where(name: name).destroy_all
  end
  base
end

# Distinct doc_types that currently have a same-name document override — i.e. the
# doc_types an "apply to all" save would reset. `.size` is the warning count.
def shadow_override_doc_types(name)
  document_designs
    .joins(:paragraph_styles)
    .where(design_paragraph_styles: { name: name })
    .distinct
    .pluck(:doc_type)
end
```

- [ ] **Step 4: Run, verify pass**

Run: `bin/rails test test/models/design/theme_test.rb`
Expected: PASS (all, including pre-existing).

- [ ] **Step 5: Commit**

```bash
git add app/models/design/theme.rb test/models/design/theme_test.rb
git commit -m "feat(design): Theme save-scope helpers (doc_type fan-out, all-write, shadow count)"
```

---

### Task 2: panel_update — dispatch on apply_scope

**Files:**
- Modify: `app/controllers/concerns/design/document_design_editing.rb` (`panel_update`, ~line 59)
- Test: `test/controllers/design/document_designs_panel_test.rb`

- [ ] **Step 1: Write failing tests**

Append to `test/controllers/design/document_designs_panel_test.rb` (the class signs in `:david` and builds `@theme`/`@ps`/`@dd` with `doc_type: "chapter"` in `setup`):

```ruby
test "panel_update without apply_scope fans out to same-doc_type designs and leaves base" do
  s2 = @theme.paper_sizes.create!(size_name: "사륙판", width_mm: 128, height_mm: 188)
  ch2 = s2.document_designs.create!(doc_type: "chapter")
  base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)

  patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: base.id),
        params: { paragraph_style: { font_size: 13 } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

  assert_response :success
  assert_equal "13.0", @dd.paragraph_styles.find_by(name: "body").font_size.to_s
  assert_equal "13.0", ch2.paragraph_styles.find_by(name: "body").font_size.to_s
  assert_equal 10, base.reload.font_size, "base untouched on scoped save"
end

test "panel_update with apply_scope=all writes the base and clears overrides" do
  base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
  @dd.paragraph_styles.create!(name: "body", font_size: 8)

  patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: base.id),
        params: { paragraph_style: { font_size: 22 }, apply_scope: "all" },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

  assert_response :success
  assert_equal 22, base.reload.font_size
  assert_equal 0, @dd.paragraph_styles.where(name: "body").count, "shadow override cleared"
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rails test test/controllers/design/document_designs_panel_test.rb`
Expected: FAIL — scoped save currently mutates the base / does not fan out, so assertions on `ch2` and `base untouched` fail.

- [ ] **Step 3: Implement**

In `app/controllers/concerns/design/document_design_editing.rb`, replace the body of `panel_update` (currently `style = find_panel_style(...)` then `if style.update(paragraph_style_params)`):

```ruby
def panel_update
  style = find_panel_style(params[:level], params[:style_id])
  style.assign_attributes(paragraph_style_params) # validate without persisting the clicked record
  if style.valid?
    name = style.name_was || style.name
    if params[:apply_scope] == "all"
      @theme.apply_paragraph_style_to_all!(name, paragraph_style_params)
    else
      @theme.apply_paragraph_style_to_doc_type!(@document_design.doc_type, name, paragraph_style_params)
    end
    Design::ThemeDbExportService.new(@theme).export!
    result = Design::PreviewService.new(@document_design, paper_size: @paper_size).generate
    preview = if result[:success]
      Design::Views::DocumentDesigns::Preview.new(
        document_design: @document_design, paper_size: @paper_size,
        jpg_url: helpers.preview_jpg_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, t: Time.now.to_i),
        overlay_data: result[:overlay_data], page_width: result[:page_width], page_height: result[:page_height],
        style_urls: build_style_urls)
    else
      Design::Views::DocumentDesigns::PreviewError.new(error: result[:error])
    end
    render turbo_stream: turbo_stream.replace("preview_frame", html: preview.call.html_safe)
  else
    render_paragraph_style_panel(
      style,
      panel_update_url: helpers.panel_update_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: params[:level], style_id: style.id),
      revert_url: document_style_revert_url(style, params[:level]),
      status: :unprocessable_entity)
  end
end
```

Note: `name_was` is the persisted name (override key) — falls back to `name` for a not-yet-renamed record.

- [ ] **Step 4: Run, verify pass**

Run: `bin/rails test test/controllers/design/document_designs_panel_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/concerns/design/document_design_editing.rb test/controllers/design/document_designs_panel_test.rb
git commit -m "feat(design): panel_update dispatches save scope (doc_type default vs all)"
```

---

### Task 3: Panel view — checkbox, helper text, shadow count, confirm wiring + i18n

**Files:**
- Modify: `app/components/design/views/paragraph_styles/panel.rb`
- Modify: `app/components/design/views/paragraph_styles/edit_page.rb`
- Modify: `app/controllers/concerns/design/document_design_editing.rb` (`render_paragraph_style_panel`)
- Modify: `config/locales/ko.yml`, `config/locales/en.yml`
- Test: `test/components/design/paragraph_style_panel_test.rb`

- [ ] **Step 1: Add i18n keys**

Under `panel:` in `config/locales/ko.yml` (after `revert:`):

```yaml
      apply_to_all: "모든 문서 유형에 적용"
      apply_to_all_hint: "기본값: 이 문서 유형에만 (모든 판형)"
      apply_to_all_confirm: "개 문서 유형의 개별 설정이 초기화됩니다. 계속할까요?"
```

Under `panel:` in `config/locales/en.yml`:

```yaml
      apply_to_all: "Apply to all document types"
      apply_to_all_hint: "Default: only this document type (all paper sizes)"
      apply_to_all_confirm: " document type(s) will be reset. Continue?"
```

(The confirm string is a suffix; the Stimulus controller prepends the count, e.g. `2` + `" document type(s) will be reset. Continue?"`. The KO string needs no leading space — `2개 문서…`. Keep the literal leading space in the EN value.)

- [ ] **Step 2: Write failing view test**

First **extend the existing private `render_panel` helper** in `test/components/design/paragraph_style_panel_test.rb` to forward the two new kwargs (it already stubs `helpers.form_authenticity_token`, which the Panel needs — the new tests MUST go through it, not call `.call` directly, or they raise on the missing request context):

```ruby
def render_panel(style, revert_url: nil, editable: true, document_design: nil, save_scope_shadow_count: 0)
  component = Design::Views::ParagraphStyles::Panel.new(
    paragraph_style: style,
    panel_update_url: "/test/panel_update",
    back_url: "/test/back",
    revert_url: revert_url,
    editable: editable,
    document_design: document_design,
    save_scope_shadow_count: save_scope_shadow_count
  )
  component.define_singleton_method(:helpers) do
    obj = Object.new
    def obj.form_authenticity_token = "test-token"
    obj
  end
  component.call
end
```

Then append these tests:

```ruby
test "renders the apply-to-all checkbox with shadow count when document_design is supplied" do
  theme = Design::Theme.create!(name: "PV #{SecureRandom.hex(3)}", locale: "ko")
  ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  dd = ps.document_designs.create!(doc_type: "chapter")
  style = theme.base_paragraph_styles.create!(name: "body")

  html = render_panel(style, document_design: dd, save_scope_shadow_count: 2)

  assert_includes html, %(name="apply_scope")
  assert_includes html, %(value="all")
  assert_includes html, "design--save-scope"
  assert_includes html, %(data-design--save-scope-count-value="2")
  assert_match %r{data-controller="design--panel-autosave design--save-scope"}, html
end

test "omits the checkbox when no document_design is supplied" do
  style = Design::ParagraphStyle.new(name: "body")
  html = render_panel(style)
  refute_includes html, %(name="apply_scope")
end
```

- [ ] **Step 3: Run, verify failure**

Run: `bin/rails test test/components/design/paragraph_style_panel_test.rb`
Expected: FAIL — `unknown keyword: :document_design`.

- [ ] **Step 4: Implement Panel**

In `app/components/design/views/paragraph_styles/panel.rb`:

Update `initialize`:

```ruby
def initialize(paragraph_style:, panel_update_url:, back_url:, revert_url: nil, editable: true,
               document_design: nil, save_scope_shadow_count: 0)
  @paragraph_style = paragraph_style
  @panel_update_url = panel_update_url
  @back_url = back_url
  @revert_url = revert_url
  @editable = editable
  @document_design = document_design
  @save_scope_shadow_count = save_scope_shadow_count
end
```

Change the form's `data:` in `render_form` to register both controllers and order the actions (save-scope first so its confirm can stop autosave):

```ruby
form(action: @panel_update_url, method: "post", class: "flex flex-col gap-5",
     data: { controller: "design--panel-autosave design--save-scope",
             action: "submit->design--save-scope#confirmScope submit->design--panel-autosave#save" }) do
```

In `render_actions`, render the checkbox before the Save button (only in document context + editable):

```ruby
def render_actions
  div(class: "flex flex-col gap-2") do
    save_scope_field if @document_design && @editable
    div(class: "flex items-center gap-3") do
      if @editable
        button(type: "submit", class: "inline-flex items-center rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700") { I18n.t("design.shared.save") }
        span(class: "text-xs text-slate-500 hidden", data: { "design--panel-autosave-target": "status" })
      end
      if @revert_url && @editable
        a(href: @revert_url, data: { turbo_method: :delete, turbo_frame: "properties_panel" },
          class: "text-sm text-red-600 hover:underline ml-auto") { I18n.t("design.panel.revert") }
      end
    end
  end
end

def save_scope_field
  label(class: "flex items-start gap-2 text-sm text-slate-700") do
    input(type: "checkbox", name: "apply_scope", value: "all",
          class: "mt-0.5 rounded border-slate-300",
          data: { "design--save-scope-target": "checkbox" })
    span do
      span(class: "font-medium") { I18n.t("design.panel.apply_to_all") }
      span(class: "block text-xs text-slate-500") { I18n.t("design.panel.apply_to_all_hint") }
    end
  end
end
```

Add the controller's data values on the form element so the JS can read the count + message. Extend the form `data:` hash:

```ruby
data: { controller: "design--panel-autosave design--save-scope",
        action: "submit->design--save-scope#confirmScope submit->design--panel-autosave#save",
        "design--save-scope-count-value": @save_scope_shadow_count,
        "design--save-scope-message-value": I18n.t("design.panel.apply_to_all_confirm") }
```

(An unchecked checkbox submits nothing, so `apply_scope` is absent → controller default `"doc_type"`. No hidden companion field is wanted here.)

- [ ] **Step 5: Thread document_design + count from the controller and EditPage**

In `app/controllers/concerns/design/document_design_editing.rb`, update `render_paragraph_style_panel` to pass them:

```ruby
def render_paragraph_style_panel(style, panel_update_url:, revert_url:, status: :ok)
  back_url = helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design)
  render Design::Views::ParagraphStyles::Panel.new(
    paragraph_style: style,
    panel_update_url: panel_update_url,
    back_url: back_url,
    revert_url: revert_url,
    editable: editable?,
    document_design: @document_design,
    save_scope_shadow_count: @theme.shadow_override_doc_types(style.name).size
  ), status: status
end
```

In `app/components/design/views/paragraph_styles/edit_page.rb`, pass them when constructing the Panel (the `EditPage` already holds `@document_design` and `@theme`):

```ruby
render Design::Views::ParagraphStyles::Panel.new(
  paragraph_style: @paragraph_style,
  panel_update_url: @panel_update_url,
  back_url: @back_url,
  revert_url: @revert_url,
  editable: @editable,
  document_design: @document_design,
  save_scope_shadow_count: @theme.shadow_override_doc_types(@paragraph_style.name).size
)
```

- [ ] **Step 6: Run, verify pass**

Run: `bin/rails test test/components/design/paragraph_style_panel_test.rb test/controllers/design/document_designs_panel_test.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/components/design/views/paragraph_styles/panel.rb app/components/design/views/paragraph_styles/edit_page.rb app/controllers/concerns/design/document_design_editing.rb config/locales/ko.yml config/locales/en.yml test/components/design/paragraph_style_panel_test.rb
git commit -m "feat(design): apply-to-all checkbox + confirm wiring in the style panel"
```

---

### Task 4: design--save-scope Stimulus controller

**Files:**
- Create: `app/javascript/design-controllers/design/save_scope_controller.js`

- [ ] **Step 1: Implement the controller**

```js
import { Controller } from "@hotwired/stimulus"

// Guards the "apply to all document types" save: when the box is checked and at
// least one same-name per-doc_type override would be reset, ask for confirmation.
// Registered ahead of panel-autosave on the form's submit action, so cancelling
// here (preventDefault + stopImmediatePropagation) stops the autosave handler.
export default class extends Controller {
  static targets = ["checkbox"]
  static values = { count: Number, message: String }

  confirmScope(event) {
    if (!this.hasCheckboxTarget || !this.checkboxTarget.checked) return
    if (this.countValue <= 0) return
    if (!window.confirm(`${this.countValue}${this.messageValue}`)) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }
}
```

- [ ] **Step 2: Verify registration**

The host eager-loads via `eagerLoadControllersFrom("design-controllers", application)` (`app/javascript/design/index.js`), so a file at `design-controllers/design/save_scope_controller.js` auto-registers as `design--save-scope`. No manifest edit needed.

Run: `bin/rails test test/components/design/paragraph_style_panel_test.rb`
Expected: PASS (asserts the `design--save-scope` wiring rendered in Task 3).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/design-controllers/design/save_scope_controller.js
git commit -m "feat(design): save-scope Stimulus controller (confirm before resetting overrides)"
```

---

### Task 5: Full suite + freshness + manual verification

**Files:** none (verification only)

- [ ] **Step 1: Run the whole gem suite**

Run: `bin/rails test`
Expected: all green (367+ runs, plus the new tests), including `DesignTailwindBuildFreshnessTest` (no CSS change here, so it stays green).

- [ ] **Step 2: Manual smoke (the running book_design app on :3009)**

Drive the editor (reuse `scratchpad/editor-e2e`): open a `chapter` style edit, save with the box **unchecked** → confirm the override appears on the same doc_type in another paper size and the theme base is unchanged. Save another style with the box **checked** after creating a shadow → confirm the `confirm()` dialog fires and, on accept, the base updates and overrides clear. Capture a screenshot of the checkbox under the Save button.

- [ ] **Step 3: Commit any fixes, then ship**

Ship per the existing flow: push the `design` gem, then bump `book_design` and `book_write` `Gemfile.lock` to the new revision and push (use `mise exec ruby@3.4.7 -- bundle update design --conservative` in `book_write`).

---

## File-responsibility summary

- `app/models/design/theme.rb` — the three scope methods (all persistence logic).
- `app/controllers/concerns/design/document_design_editing.rb` — `panel_update` dispatch + `render_paragraph_style_panel` plumbing.
- `app/components/design/views/paragraph_styles/panel.rb` — checkbox, helper text, form data-wiring.
- `app/components/design/views/paragraph_styles/edit_page.rb` — passes `document_design` + shadow count to the Panel.
- `app/javascript/design-controllers/design/save_scope_controller.js` — confirm guard.
- `config/locales/{ko,en}.yml` — label/hint/confirm strings.
- Tests: `theme_test.rb`, `document_designs_panel_test.rb`, `paragraph_style_panel_test.rb`.
