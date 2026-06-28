# Paragraph-style edit form redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the paragraph-style edit form into compact pastel group boxes with inline (label | control) rows so it fits beside the preview without scrolling.

**Architecture:** Pure markup + scoped-CSS change to one Phlex component, `Design::Views::ParagraphStyles::Fields`. Each group becomes a `fieldset` (tinted box, legend chip top-left); fields render inline two-per-row; `font_section` + `text_section` merge. Field names, inputs, and Stimulus controllers are unchanged, so existing behavior/tests hold.

**Tech Stack:** Phlex 2 components, scoped Tailwind v4 (`.design-studio`), the gem's dummy-app test suite (minitest), Playwright for visual verification.

**Spec:** `docs/superpowers/specs/2026-06-28-paragraph-style-form-redesign-design.md`

---

## File structure

- **Modify:** `app/components/design/views/paragraph_styles/fields.rb` — the whole component: new `group_box`/inline-`field_row` helpers, merged 글꼴·텍스트, per-group tint, full-row exceptions for font/color, border editors inside the 테두리 box.
- **Modify:** `app/assets/builds/design.css` — rebuilt scoped CSS (new utility classes).
- **Modify/Add test:** `test/components/design/fields_layout_test.rb` (new) — assert the boxed/merged/inline structure renders.
- **Unchanged:** Stimulus controllers, the Panel/EditPage wrappers, i18n keys (reuse existing `design.fields.*`; the merged box can reuse an existing label or add one new key `design.fields.type_text`).

---

### Task 1: Boxed, inline, merged form layout

**Files:**
- Modify: `app/components/design/views/paragraph_styles/fields.rb`
- Test: `test/components/design/fields_layout_test.rb`

- [ ] **Step 1: Write the failing test** — render `Fields` for a normal style and assert the new structure.

```ruby
require "test_helper"

class Design::FieldsLayoutTest < ActiveSupport::TestCase
  def render_fields(name: "title")
    theme = Design::Theme.create!(name: "FX #{SecureRandom.hex(3)}", locale: "ko")
    style = theme.base_paragraph_styles.create!(name: name, font_size: 24, text_color: "CMYK=0,0,0,100", border_thickness: 5)
    Design::Views::ParagraphStyles::Fields.new(paragraph_style: style).call
  end

  test "groups render as fieldset boxes with legends" do
    html = render_fields
    assert_includes html, "<fieldset"
    [ "기본 정보", "굵게", "간격", "채우기", "테두리", "여백" ].each { |t| assert_includes html, t }
  end

  test "font and text are merged into one group" do
    html = render_fields
    # one merged legend, and both a font select and the text color/align controls live together
    assert_equal 1, html.scan("글꼴 · 텍스트").size
    assert_includes html, %(name="paragraph_style[font]")
    assert_includes html, %(name="paragraph_style[text_color]")
  end

  test "fields are inline rows (label + control on one line)" do
    html = render_fields
    # the inline row wrapper carries the marker class
    assert_includes html, "ps-field"      # inline row helper class
    assert_includes html, %(name="paragraph_style[font_size]")
  end

  test "border editors + corner radius stay in the border box" do
    html = render_fields
    assert_includes html, "design--border-side-editor"
    assert_includes html, "design--corner-editor"
    assert_includes html, %(name="paragraph_style[corner_radius]")
  end
end
```

- [ ] **Step 2: Run test, verify it fails**

Run: `bin/rails test test/components/design/fields_layout_test.rb`
Expected: FAIL (no `<fieldset>` / "글꼴 · 텍스트" / `ps-field` yet).

- [ ] **Step 3: Rewrite `Fields`** — replace the section helpers with:
  - `group_box(legend, tint, &block)`: a `fieldset` (tint bg+border) with a `legend` chip; tints keyed per group (basic=blue, type=green, bold=amber, space=violet, fill=pink, border=cyan, pad=orange, table=slate).
  - `field_row(label, span: false, &block)`: inline `div.ps-field` = right-aligned fixed-width `label` + the control; `span: true` makes it full-width (use for `font_select` and every `color_row`).
  - `rows(&block)`: the 2-col grid wrapper inside a box.
  - `view_template`: emit boxes in spec order; **merge** `font_section`+`text_section` into one `type_text` box; keep `table_cell` conditional; keep border editors + `corner_radius` inside the border box.
  - Update `number_field`/`select_field`/`text_field`/`font_select`/`color_row` to render through the inline `field_row` (and pass `span: true` where noted). Keep all `name=`s and Stimulus data attributes identical.

- [ ] **Step 4: Run test, verify it passes**

Run: `bin/rails test test/components/design/fields_layout_test.rb`
Expected: PASS.

- [ ] **Step 5: Rebuild scoped CSS** (new utility classes from the rewrite)

Run the in-repo rebuild (mirror of the freshness test):
```bash
bin/rails runner 'require "tailwindcss/ruby"; require Design::Engine.root.join("lib/design/tailwind_scoper"); require "tmpdir"; root=Design::Engine.root; Dir.mktmpdir{|d| raw=File.join(d,"r.css"); system(Tailwindcss::Ruby.executable.to_s,"-i",root.join("app/assets/tailwind/design.css").to_s,"-o",raw,"--minify",exception:true); File.write(root.join("app/assets/builds/design.css"), Design::TailwindScoper.scope(File.read(raw), under:".design-studio"))}'
```

- [ ] **Step 6: Run the impacted suites**

Run: `bin/rails test test/components/design/fields_layout_test.rb test/components/design/paragraph_style_panel_test.rb test/controllers/design/paragraph_styles_form_test.rb test/design_tailwind_build_freshness_test.rb`
Expected: all green (field names/inputs unchanged → form tests still pass; freshness passes after rebuild).

- [ ] **Step 7: Commit**

```bash
git add app/components/design/views/paragraph_styles/fields.rb app/assets/builds/design.css test/components/design/fields_layout_test.rb
git commit -m "feat(studio): boxed, inline paragraph-style form that fits the preview height"
```

---

### Task 2: Visual verification

**Files:** none (uses `book_design/e2e` + a running server)

- [ ] **Step 1:** With book_design on :3009 (gem loaded via local override → restart it), get an editor path: `bin/rails e2e:prepare | tail -1`.
- [ ] **Step 2:** Screenshot the EditPage form region at the real preview height; confirm: all groups visible **without scrolling**, pastel boxes legible, legends on the box border, inline rows, the 테두리 box complete, color field not overflowing.
- [ ] **Step 3:** If anything overflows the preview height or a row is too tight, adjust paddings/row gap/label width in `fields.rb`, rebuild CSS (Task 1 Step 5), re-shoot.

---

### Task 3: Ship

- [ ] **Step 1:** Full gem suite green: `bin/rails test`.
- [ ] **Step 2:** Push the design gem `main`.
- [ ] **Step 3:** Re-bump `design` in book_design + book_write `Gemfile.lock` (the established follow-up) and push each.
