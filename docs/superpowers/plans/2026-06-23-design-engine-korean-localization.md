# Design Engine Korean Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the design-engine authoring UI in Korean by replacing hardcoded English in the remaining design view components with `I18n.t("design.…")` calls, adding ko/en translations, and defaulting book_design to `:ko`.

**Architecture:** Extend the gem's existing i18n (themes UI is already localized; `around_action :switch_design_locale` already applies `Design.locale_for`, and book_design wires `locale_for = -> { I18n.locale }`). Add keys under `design.*`, translate option *labels* while keeping stored *values* English, and set book_design `default_locale = :ko`.

**Tech Stack:** Rails 8.1 engine, Phlex components, Rails I18n (YAML locale files), Minitest.

**Spec:** `design/docs/superpowers/specs/2026-06-23-design-engine-korean-localization-design.md`
**Canonical translations:** `design/docs/i18n-ko-glossary.md` — the implementer transcribes its **Korean** column into `ko.yml` and its **English** column into `en.yml`. Do NOT invent strings; use the glossary verbatim.

**Repos:**
- `DG` = `/Users/mskim/Development/ruby/gems/design` (gem, branch `main`) — almost all work.
- `BD` = `/Users/mskim/Development/book/book_design` (host) — Task 6 only (`:ko` default).

**Test command:** `bin/rails test` (full) / `bin/rails test test/path/x_test.rb` (single), from each repo root. Minitest only.

**Conventions (verified):**
- Components call **`I18n.t("design.<ns>.<key>")`** directly (see `app/components/design/views/themes/index.rb`). Use that form, not `t(...)`.
- Both `config/locales/ko.yml` and `config/locales/en.yml` exist and mirror each other under `design.*`. EVERY new key goes in BOTH (en.yml = the glossary's English, the fallback).
- Stage only the files each task changes; commit to `main`. Never run `db:*` in BD (real data). Restart BD server only for the Task 6 visual check.

---

## File Structure

**`DG` (gem):**
- Modify components: `app/components/design/views/document_designs/{properties_panel,edit,preview,preview_error}.rb`, `paragraph_styles/{fields,panel,form}.rb`, `paper_sizes/edit.rb`.
- Modify `config/locales/ko.yml` + `config/locales/en.yml` — add `design.{properties_panel,fields,editor,preview,panel,paper_sizes,options}.*`.
- Create tests: `test/i18n/locale_parity_test.rb`, `test/components/design/localization_test.rb`.

**`BD` (host):**
- Modify `config/application.rb` — `default_locale = :ko`, `available_locales = [:ko, :en]`.
- Create `config/locales/ko.yml` (stub) so `:ko` is a valid load target.

**Translation key namespaces** (mirror the glossary sections):
`design.properties_panel.*`, `design.fields.*`, `design.editor.*`, `design.preview.*`, `design.panel.*`, `design.paper_sizes.*`, `design.options.<attr>.<value>`.

---

## Task 1 — Option-label i18n mechanism (the value/label rule)

**Files:** `DG/app/components/design/views/document_designs/properties_panel.rb` (`select_field` ~509), `paragraph_styles/fields.rb` (`select_field` ~150), `config/locales/{ko,en}.yml`, `test/components/design/localization_test.rb` (new)

> The crux: `select_field` currently renders `option(value: opt) { opt }` — value == visible label. We keep `value: opt` (the stored DB token) and translate ONLY the visible label.

- [ ] **Step 1: Write the failing value-guard test**

Create `test/components/design/localization_test.rb`:
```ruby
require "test_helper"

class Design::LocalizationTest < ActiveSupport::TestCase
  def panel(doc_type: "toc")
    theme = Design::Theme.create!(name: "L #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: doc_type)
    c = Design::Views::DocumentDesigns::PropertiesPanel.new(theme: theme, paper_size: ps, document_design: dd, editable: true)
    # REQUIRED: the panel calls helpers.*_path during render (no request context
    # in a unit test). Stub its URL methods, EXACTLY as the existing
    # test/components/design/properties_panel_test.rb#render_panel does:
    c.define_singleton_method(:form_action_url) { "/x" }
    c.define_singleton_method(:preview_url) { "/x/preview" }
    c.define_singleton_method(:csrf_token) { "test-token" }
    c.define_singleton_method(:typography_panel_url) { |o| "/x/panel/#{o.id}" }
    c.define_singleton_method(:typography_override_url) { |_n| "/x/override" }
    c.define_singleton_method(:typography_new_style_url) { "/x/new" }
    c.call
  end

  test "v-align select keeps English values but shows Korean labels in :ko" do
    html = I18n.with_locale(:ko) { panel }
    # stored values stay English (the renderer reads these):
    assert_includes html, %(value="center")
    assert_includes html, %(value="top")
    assert_includes html, %(value="bottom")
    # visible labels are Korean:
    assert_includes html, "가운데"
    assert_includes html, "아래"
  end
end
```

- [ ] **Step 2: Run it; verify it FAILS** — `bin/rails test test/components/design/localization_test.rb` (labels are English).

- [ ] **Step 3: Add the `i18n_scope` option to both `select_field` helpers**

In `properties_panel.rb` `select_field`, change the signature + option rendering:
```ruby
        def select_field(label_text, attr, options, i18n_scope: nil)
          field_row(label_text) do
            select(name: "document_design[#{attr}]",
                   class: "border border-slate-300 rounded px-2 py-1 text-sm w-full", **disabled_attr) do
              current = @document_design.public_send(attr)
              options.each do |opt|
                label = i18n_scope ? I18n.t("design.options.#{i18n_scope}.#{opt}") : opt
                option(value: opt, selected: opt == current) { label }
              end
            end
          end
        end
```
Apply the equivalent change to `fields.rb` `select_field(label_text, attr, options, include_blank: nil, i18n_scope: nil)` (keep `include_blank`).

- [ ] **Step 4: Pass `i18n_scope` at the option-bearing call sites + add `design.options.*` keys**

In `properties_panel.rb`, the v-align selects become `select_field(I18n.t("design.properties_panel.heading_v_align"), :heading_v_align, %w[center top bottom], i18n_scope: "v_align")` and the toc one `i18n_scope: "v_align"`. (Heading-background type radio + cover_type + anchor are handled in Task 2; here just wire `v_align` so the test passes.)
Add to `config/locales/ko.yml` and `en.yml` (values from the glossary "Select option labels" table):
```yaml
# ko.yml
ko: { design: { options: { v_align: { center: "가운데", top: "위", bottom: "아래" } } } }
# en.yml mirrors with English: center: "Center", top: "Top", bottom: "Bottom"
```
(Use proper nested YAML, not flow style — shown compact here.)

- [ ] **Step 5: Run the test; verify it PASSES.**

- [ ] **Step 6: Commit** (the two helper files + both yml + the test).
```bash
cd /Users/mskim/Development/ruby/gems/design
git add app/components/design/views/document_designs/properties_panel.rb app/components/design/views/paragraph_styles/fields.rb config/locales/ test/components/design/localization_test.rb
git commit -m "feat(i18n): localized select-option labels (values stay English)"
```

---

## Task 2 — Localize PropertiesPanel

**Files:** `DG/app/components/design/views/document_designs/properties_panel.rb`, `config/locales/{ko,en}.yml`, `test/components/design/localization_test.rb`

- [ ] **Step 1: Add a failing render-in-ko test** (append to the localization test):
```ruby
  test "properties panel renders Korean labels, no English leftovers" do
    html = I18n.with_locale(:ko) { panel }
    assert_includes html, "레이아웃"          # Layout tab
    assert_includes html, "본문 줄 수"         # Body Line Count
    assert_includes html, "단락정의"           # Typography (user glossary)
    refute_includes html, ">Layout<"
    refute_includes html, "Body Line Count"
    assert_not_includes html, "translation missing"
  end
```
Run → FAIL.

- [ ] **Step 2: Replace every literal in `properties_panel.rb` with `I18n.t("design.properties_panel.<key>")`**

Walk the component top to bottom. For each visible string in the **Properties Panel** glossary section, replace the literal with `I18n.t("design.properties_panel.<key>")`. Key naming: snake_case of the English (e.g. `Layout`→`layout`, `Heading V-Align`→`heading_v_align`, `Body Line Count`→`body_line_count`, `Gutter (pt)`→`gutter`, `Page Background (Bleed)`→`page_background`, `Extends 3mm…`→`page_background_hint`, `Default (Bottom Left)`→`anchor_default`, `Has Document Cover`→`has_document_cover`, `Header Left`→`header_left`, etc.). The tab triggers `Layout/Typography/Header/Footer`, section `h2`/`h3` headings, field labels, checkbox labels, helper text, the `Current: %{filename}` (use `I18n.t("design.properties_panel.current_image", filename: @document_design.heading_bg_image.filename)`), and the `Add Style`/`+ Add` buttons. **Note:** both `"Header/Footer"` (tab) and `"Header / Footer"` (section h2) → the SAME key `design.properties_panel.header_footer`.
For the heading-background type radio (`color/image/gradient`), cover_type, and anchor-position dropdown, route their option labels through `design.options.{bg_type,cover_type,anchor}.<value>` (same value-stays-English rule as Task 1).

- [ ] **Step 3: Add all `design.properties_panel.*` + the new `design.options.*` keys to BOTH `ko.yml` (Korean from glossary) and `en.yml` (English from glossary).**

- [ ] **Step 4: Run the test; verify it PASSES** (Korean present, no English leftovers, no missing).

- [ ] **Step 5: Commit** (`properties_panel.rb` + both yml + test).

---

## Task 3 — Localize paragraph-style Fields

**Files:** `DG/app/components/design/views/paragraph_styles/fields.rb`, `config/locales/{ko,en}.yml`, the localization test

- [ ] **Step 1: Failing test** (append):
```ruby
  test "fields render Korean, no English leftovers" do
    theme = Design::Theme.create!(name: "F #{SecureRandom.hex(3)}", locale: "ko")
    style = theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    html = I18n.with_locale(:ko) { Design::Views::ParagraphStyles::Fields.new(paragraph_style: style, editable: true).call }
    assert_includes html, "자간"       # Tracking
    assert_includes html, "어간"       # Space Width (user glossary)
    assert_includes html, "행간"       # Line Spacing
    refute_includes html, "Tracking"
    refute_includes html, "Identity"
    assert_not_includes html, "translation missing"
  end
```
Run → FAIL.

- [ ] **Step 2: Replace every literal in `fields.rb` with `I18n.t("design.fields.<key>")`** — all field labels, section headings (Identity/Font/Text/Bold & Emphasis/Spacing/Fill/Border/Padding), and the Border-Sides / Rounded-Corners glyph labels (Top/Bottom/Left/Right). For the Align / Fill Type / Gradient Dir. / Corner Radius selects, route option labels through `design.options.{text_align,fill_type,gradient_dir,corner_radius}.<value>`.

- [ ] **Step 3: Add `design.fields.*` + the new `design.options.*` keys to BOTH yml** (from glossary).

- [ ] **Step 4: Run the test; verify PASS.**

- [ ] **Step 5: Commit.**

---

## Task 4 — Localize the standalone Editor + Preview

**Files:** `DG/app/components/design/views/document_designs/{edit,preview,preview_error}.rb`, `config/locales/{ko,en}.yml`, the localization test

**Two test seams** (the `Edit` shell renders a NESTED `PropertiesPanel`, whose own `helpers.*` calls can't be stubbed via singleton overrides on the `Edit` instance — so `Edit` can't be unit-rendered bare):

- [ ] **Step 1a: Preview/PreviewError — bare unit test** (append to `localization_test.rb`):
```ruby
  test "preview overlay labels are Korean" do
    theme = Design::Theme.create!(name: "P #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "title_page")
    html = I18n.with_locale(:ko) do
      Design::Views::DocumentDesigns::Preview.new(
        document_design: dd, paper_size: ps, jpg_url: "/x.jpg",
        overlay_data: [{ type: "heading_area", markup: "title", x: 0, y: 0, width: 50, height: 10 }],
        page_width: 100, page_height: 100, style_urls: {}
      ).call
    end
    assert_includes html, "제목"   # Title overlay label
  end
  test "preview error is Korean" do
    html = I18n.with_locale(:ko) { Design::Views::DocumentDesigns::PreviewError.new(error: "boom").call }
    assert_includes html, "미리보기 생성 실패"
    refute_includes html, "Preview generation failed"
  end
```
(`Preview`/`PreviewError` have NO `helpers.*` calls → render bare.) Run → FAIL.

- [ ] **Step 1b: Edit — integration test** (new `test/controllers/design/editor_locale_test.rb`, an `ActionDispatch::IntegrationTest` with a real view context that renders the nested panel):
```ruby
require "test_helper"
class Design::EditorLocaleTest < ActionDispatch::IntegrationTest
  test "edit page renders Korean editor chrome under :ko" do
    sign_in :david rescue nil
    th = Design::Theme.create!(name: "E #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    ps = th.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")
    I18n.with_locale(:ko) do
      get design.edit_theme_paper_size_document_design_path(th, ps, dd)
    end
    assert_response :success
    assert_includes response.body, "미리보기"          # Preview
    assert_includes response.body, "기본 텍스트 스타일"  # Base Text Styles
    refute_includes response.body, ">Preview<"
  end
end
```
> Match `sign_in`/fixtures to the gem's existing controller tests (`test/controllers/design/document_designs_override_test.rb`). The around_action applies the locale; if the dummy app's `locale_for` overrides `I18n.with_locale`, set the dummy app's default to `:ko` for the test (or stub `Design.config.locale_for` to `-> { :ko }`). Run → FAIL.

- [ ] **Step 2: Localize the three components.**
- `edit.rb`: breadcrumb/section headings + `Preview`, `Base Text Styles (inherited from theme)`, `Document Styles (overrides)`, `Edit →`, the shared-styles sentence, and the `theme page` link text → `design.editor.*` keys.
- `preview.rb`: the `HEADING_LABELS` hash values (`Title/Subtitle/Author/Publisher`) → `I18n.t("design.preview.overlay.<key>")`; the `|| "Heading"` / `|| "Body"` fallbacks and `|| "TOC Entry"` and `"Generating preview..."` → `design.preview.*`. (Keep the `style_name&.capitalize` fallback for unknown styles.)
- `preview_error.rb`: `Preview generation failed` → `design.preview.generation_failed`.

- [ ] **Step 3: Add `design.editor.*` + `design.preview.*` keys to BOTH yml** (from glossary, incl. the "Added in spec review" preview rows).

- [ ] **Step 4: Run; PASS.**  **Step 5: Commit.**

---

## Task 5 — Localize Paper-size editor + paragraph Panel/Form

**Files:** `DG/app/components/design/views/paper_sizes/edit.rb`, `paragraph_styles/{panel,form}.rb`, `config/locales/{ko,en}.yml`, the localization test

- [ ] **Step 1: Failing test** (append) — render the paragraph `Panel` under `:ko`; assert `저장` (Save), `← 뒤로` (Back), `기본값으로 되돌리기` (Revert to base) present, English absent. Run → FAIL.
  > **Constructor + stub (REQUIRED, mirror `test/components/design/paragraph_style_panel_test.rb#render_panel`):** `Panel.new(paragraph_style: style, panel_update_url: "/x", back_url: "/x", revert_url: "/x", editable: true)` then `c.define_singleton_method(:helpers) { o = Object.new; def o.form_authenticity_token = "t"; o }` before `.call` (the Panel calls `helpers.form_authenticity_token`). For `paper_sizes/edit.rb`'s test, stub its `helpers` URL calls the same way.

- [ ] **Step 2: Localize.**
- `paragraph_styles/panel.rb`: `← Back`, `New Style`, `Please fix the following errors:`, `Save`, `Revert to base` → `design.panel.*`.
- `paragraph_styles/form.rb`: `Save`, `Cancel` → `design.panel.*`.
- `paper_sizes/edit.rb`: `Margins (mm)`, `Binding Margin (mm)`, `Body Line Count`, `TOC Page Count`, `Base Text Styles`, `Top/Bottom/Left/Right` → `design.paper_sizes.*` (reuse `design.fields.top/bottom/left/right` if you prefer one source — but keep it simple: a `design.paper_sizes.*` set is fine).

- [ ] **Step 3: Add `design.panel.*` + `design.paper_sizes.*` keys to BOTH yml.**

- [ ] **Step 4: Run; PASS.**  **Step 5: Commit.**

---

## Task 6 — Parity + no-leftover guards, book_design :ko, ship

**Files:** `DG/test/i18n/locale_parity_test.rb` (new), `BD/config/application.rb`, `BD/config/locales/ko.yml` (new)

- [ ] **Step 1: Key-parity test** — create `test/i18n/locale_parity_test.rb`:
```ruby
require "test_helper"
require "yaml"

class LocaleParityTest < ActiveSupport::TestCase
  def flatten(h, prefix = "")
    h.flat_map { |k, v| v.is_a?(Hash) ? flatten(v, "#{prefix}#{k}.") : ["#{prefix}#{k}"] }
  end

  test "ko.yml and en.yml have identical design.* key sets" do
    root = Design::Engine.root.join("config/locales")
    ko = flatten(YAML.load_file(root.join("ko.yml")).dig("ko", "design") || {}).sort
    en = flatten(YAML.load_file(root.join("en.yml")).dig("en", "design") || {}).sort
    assert_equal en, ko, "ko/en key mismatch: only-en=#{(en-ko).inspect} only-ko=#{(ko-en).inspect}"
  end
end
```
Run → must PASS (if it fails, a key is in one yml but not the other; fix the yml from Tasks 1–5).

- [ ] **Step 2: No-English-leftover guard** — append to `test/components/design/localization_test.rb` a test that renders the UNIT-renderable in-scope components under `:ko` (PropertiesPanel, Fields, Panel, Preview, PreviewError, paper_sizes/edit — reuse the SAME stubbed render helpers from Tasks 1/4/5, don't construct bare) and asserts none of a denylist of English labels appears (from the glossary English column: `Layout`, `Typography`, `Tracking`, `Margins`, `Base Text Styles`, `Generating preview`, …), exempting `CMYK`/`Hex`/`pt`/`mm`/`(base)`/font names. **`Edit` is covered by the Step 1b integration test, not this bare sweep** (it can't render bare). Run → PASS (retroactively validates Tasks 2–5; a leftover means a string was never `I18n.t`-converted — fix it).

- [ ] **Step 3: Run the FULL gem suite** — `bin/rails test`. Confirm 0 NEW failures (the existing controller/component tests must stay green; localization is additive).

- [ ] **Step 4: book_design `:ko` default.**
In `BD/config/application.rb`, inside `class Application`, add:
```ruby
    config.i18n.default_locale = :ko
    config.i18n.available_locales = [:ko, :en]
    config.i18n.fallbacks = [:en]
```
Create `BD/config/locales/ko.yml` with a stub root so `:ko` is a valid load target:
```yaml
ko:
  hello: "안녕하세요"
```
(book_design's own host strings are out of scope; this just makes `:ko` valid. The gem's `ko.yml` is loaded via its engine.)

- [ ] **Step 5: Verify in book_design** — restart BD server (`lsof -ti :3009 | xargs kill -9 2>/dev/null; sleep 2; nohup bin/rails server -p 3009 > /tmp/bd.log 2>&1 & sleep 14`). Fetch a chapter edit page; confirm Korean labels render:
```
curl -sL "http://127.0.0.1:3009/themes/7/paper_sizes/16/document_designs/255/edit" -o /tmp/e.html -w "edit %{http_code}\n"
grep -c "레이아웃\|단락정의\|본문 줄 수" /tmp/e.html   # expect >=1
grep -c ">Layout<\|Body Line Count" /tmp/e.html        # expect 0
```

- [ ] **Step 6: Commit + push** (PAUSE for user before pushing if desired).
```bash
cd /Users/mskim/Development/ruby/gems/design && git add test/i18n/locale_parity_test.rb test/components/design/localization_test.rb && git commit -m "test(i18n): locale parity + no-English-leftover guards"
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes" git push origin main
cd /Users/mskim/Development/book/book_design && git add config/application.rb config/locales/ko.yml && git commit -m "feat(i18n): default locale :ko" && git push origin main
# bump BD Gemfile.lock to the new gem HEAD (manual SHA swap, no bundle) + push
```

## Final verification
- [ ] `DG`: `bin/rails test` — 0 new failures; parity + no-leftover + value-guard + render-in-ko all green.
- [ ] book_design chapter/toc/title_page edit pages render Korean labels; no English leftovers; selects still POST English values (`value="center"`).
- [ ] book_write unaffected (renders English — it pins the gem but `:en` fallback covers the new keys).

## Notes / gotchas
- Translations come from `design/docs/i18n-ko-glossary.md` ONLY — transcribe verbatim, don't paraphrase. The user's glossary edits (e.g. `Typography→단락정의`, `Space Width→어간`, `Heading Lines→제목박스 높이 (본문 줄 수)`) are authoritative.
- Every new key in BOTH `ko.yml` and `en.yml` (parity test enforces this).
- Don't translate stored select values (center/top/bottom/solid/none/…) — only labels via `design.options.*`. The value-guard test enforces this.
- `Header/Footer` (tab) and `Header / Footer` (section) share one key.
- Use `I18n.t(...)` (not `t(...)`) — matches the gem's existing convention.
