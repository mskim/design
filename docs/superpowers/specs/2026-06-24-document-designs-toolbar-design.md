# Document-Designs Editor Toolbar + Doc-Type Switcher — Design Spec (Sub-project #3)

**Date:** 2026-06-24
**Status:** Approved (brainstorm) — pending spec review
**Repo:** `design` gem only. book_design + book_write inherit (they render the gem's document-design editor). No host change.
**Program context:** Sub-project **#3** of "converge the design studio onto book_design's UI." #0 (shell + host-action registry), #1 (themes area), #2 (paper-sizes area) are shipped. This ports book_design's **document-design editor toolbar + doc-type switcher** into the gem so editing one doc design lets you jump to a sibling without leaving the editor. Later: #4 paragraph-styles/style-browser, #5 table styles, #6 retire book_design `Pages::*`.

---

## Goal

Give the gem's document-design editor a **toolbar** with a clickable breadcrumb (theme + paper-size) and a **doc-type dropdown switcher** that jumps directly to a sibling doc design's edit page — matching book_design's `Shared::EditorToolbar`. Today the gem's editor has only a static breadcrumb; switching doc types means leaving the editor, going back to the theme-show grid, and clicking another card.

## Problem

The gem's `Design::Views::DocumentDesigns::Edit` renders a **static** `Design::Views::Breadcrumb` (theme → paper-size → doc_type; the doc_type crumb is plain text). There is **no in-editor doc-type switcher** — the only way to edit a different doc type is to navigate back to the theme-show interior grid and click another card. book_design's `Shared::EditorToolbar` (`app/components/shared/editor_toolbar.rb`) shows a clickable theme/paper-size breadcrumb plus a doc-type dropdown (its own `dropdown_controller.js`) that lists sibling doc designs and links to each one's editor. All of it is **pure UI** (route helpers + the `DocumentDesign` model) — no host-only services — so it is fully gem-movable.

## Key findings (from exploration)

- **Gem editor** (`app/components/design/views/document_designs/edit.rb`): `shell(...)` → breadcrumb (`Design::Views::Breadcrumb`, crumbs `[theme→theme_path, paper_size→edit_theme_paper_size_path, doc_type→nil]`) → `h1 doc_type` → stacked-then-`lg:flex-row` preview (lazy `turbo_frame#preview_frame`) + `PropertiesPanel` (`lg:w-[28rem]`) → document/base style lists. Note the existing paper-size crumb already links to **`edit_theme_paper_size_path`** (the gem has no per-size show page).
- **book_design toolbar** (`shared/editor_toolbar.rb`): one flex row — theme link (`theme_path`), `/`, paper-size link (`theme_paper_size_path`), `/`, and a `data-controller="dropdown"` block: a button (`@dd.doc_type` titleized + ▾) toggling a `dropdown_target="menu"` listing `@ps.document_designs.order(:doc_type)`, each an `<a>` to `edit_theme_paper_size_document_design_path`, current one highlighted `bg-blue-50 text-blue-700`. It uses **dead token classes** (`text-muted-foreground`/`hover:text-foreground`) that no-op in the gem's scoped build.
- **Stimulus in the gem:** the engine ships controllers under `app/javascript/design-controllers/design/*_controller.js` and auto-registers them via `eagerLoadControllersFrom("design-controllers", application)` (`app/javascript/design/index.js`) under the **`design--`** namespace (e.g. `design--panel-autosave`, `design--heading-elements`). Dropping a new `dropdown_controller.js` there auto-registers it as `design--dropdown` — no manual registration. `lib/design/engine.rb` adds `app/javascript` to the asset paths.
- **Doc-type labels:** the gem already has `doc_type_label(dd) = I18n.t("design.doc_types.#{dd.doc_type}", default: dd.doc_type)` (private in `themes/show.rb:165`), backed by a `design.doc_types.*` i18n namespace. book_design uses raw `doc_type.tr("_"," ").titleize`. The gem should use its **i18n labels** for consistency with theme-show.
- **Interior + reading order:** `Design::DocumentDesign.by_reading_order(designs)` sorts by `DOC_TYPE_ORDER`. `themes_controller#interior_document_designs(paper_size)` (private) = `by_reading_order(paper_size.document_designs.where.not(doc_type: COVER_PANEL_TYPES))` — the exact set the theme-show interior grid (and thus the editor's entry point) uses.

## Decisions

| # | Decision |
|---|----------|
| 1 | **New `Design::Views::DocumentDesigns::EditorToolbar` component**, rendered at the top of `Edit` **in place of** the current `Design::Views::Breadcrumb`. Keep the existing `h1`. Clickable theme + paper-size links + doc-type dropdown. |
| 2 | **Doc-type dropdown via a new `design--dropdown` Stimulus controller** (port book_design's `dropdown_controller.js`: `toggle()` + outside-click close), dropped in `app/javascript/design-controllers/design/dropdown_controller.js` (auto-registered). |
| 3 | **Switcher lists INTERIOR doc designs in READING ORDER** (exclude `COVER_PANEL_TYPES`) — the same set reachable from the theme-show interior grid. *Deliberate divergence from book_design* (which lists all doc_types via `order(:doc_type)`); chosen for consistency with the gem's interior-only navigation + canonical reading order. |
| 4 | **DRY the interior+reading-order query** into a `Design::DocumentDesign` class method (e.g. `self.interior_for(paper_size)`), used by **both** `themes_controller#interior_document_designs` and the toolbar — so the switcher and the grid can never drift. |
| 5 | **Use the gem's i18n doc-type labels** (`doc_type_label`) for the button + menu items, not `titleize`. Promote `doc_type_label(doc_type)` to `Design::Views::Base` so theme-show and the toolbar share one implementation. |
| 6 | **Explicit Tailwind utilities** (slate/blue, matching the gem's existing breadcrumb/links), **not** book_design's dead `text-muted-foreground`/`text-foreground` tokens (program rule: no token authoring). |
| 7 | **Paper-size link → `edit_theme_paper_size_path`** (matching the gem's existing editor breadcrumb), since the gem has no per-size show page. |
| 8 | **Scope: toolbar + switcher only.** Keep the gem's current stacked→`lg:flex-row` layout and **lazy** turbo-frame preview. book_design's full-height side-by-side layout + synchronous preview-on-load are **out of scope**. |

## Design

### Component (gem)

**`Design::Views::DocumentDesigns::EditorToolbar` (new)** — `initialize(theme:, paper_size:, document_design:)`. Renders one flex row:
- `a` theme name → `helpers.theme_path(@theme)` (slate link).
- `/` separator.
- `a` paper-size `display_name` → `helpers.edit_theme_paper_size_path(@theme, @paper_size)`.
- `/` separator.
- A `div(data: { controller: "design--dropdown" })` containing:
  - a `button(data: { action: "design--dropdown#toggle" })` showing `doc_type_label(@document_design.doc_type)` + a `▾`.
  - a hidden `div(data: { "design--dropdown-target": "menu" })` listing `Design::DocumentDesign.interior_for(@paper_size)`; each is an `<a href: edit_theme_paper_size_document_design_path(@theme, @paper_size, dd)>` showing `doc_type_label(dd.doc_type)`, with the current `@document_design` highlighted (`bg-blue-50 text-blue-700 font-medium`).

`Design::Views::DocumentDesigns::Edit#view_template` swaps `render Design::Views::Breadcrumb.new(...)` → `render Design::Views::DocumentDesigns::EditorToolbar.new(theme:, paper_size:, document_design:)`. The `h1` and everything below stay unchanged.

### Stimulus (gem)

**`app/javascript/design-controllers/design/dropdown_controller.js` (new)** — verbatim port of book_design's: `static targets = ["menu"]`; `toggle()` flips `menu` `hidden`; `connect()` adds a document click listener that hides the menu on outside-click; `disconnect()` removes it. Auto-registered as `design--dropdown`.

### Model (gem)

**`Design::DocumentDesign.interior_for(paper_size)` (new class method):**
```ruby
def self.interior_for(paper_size)
  by_reading_order(paper_size.document_designs.where.not(doc_type: COVER_PANEL_TYPES))
end
```
`themes_controller#interior_document_designs` is rewritten to delegate to it (no behavior change — it already does exactly this).

### Shared view helper (gem)

Move `doc_type_label(doc_type)` onto `Design::Views::Base` (`I18n.t("design.doc_types.#{doc_type}", default: doc_type)`); `themes/show.rb` keeps calling it (now inherited). The toolbar uses it. (`doc_type_label` currently takes a `dd`; the shared version takes the `doc_type` string — update the one show.rb call site to pass `dd.doc_type`.)

### i18n (gem, ko + en only)

Doc-type labels (`design.doc_types.*`) already exist. Add at most an accessible label for the dropdown button if useful (e.g. `design.document_designs.switch_doc_type` → "Switch document type" / "문서 유형 전환") used as the button `aria-label`/`title`. ko + en; identical keysets (parity test).

## Testing (Minitest)

- **Component/controller (integration, mirror `document_designs_edit_test.rb`):** the edit page renders the toolbar with a theme link (`theme_path`), a paper-size link (`edit_theme_paper_size_path`), and a doc-type dropdown button showing the current doc type's label; the dropdown menu lists the paper size's **interior** doc designs **in reading order** (assert a known order, e.g. `title_page` before `chapter` before `epilogue`), **excludes** a cover-panel type (assert no link to a seeded `front_page` design's edit path), marks the current one, and each item links to `edit_theme_paper_size_document_design_path`. The existing edit/preview/panel/heading tests stay green.
- **Model:** `DocumentDesign.interior_for(ps)` returns interior designs in reading order and excludes `COVER_PANEL_TYPES`; `themes_controller` still produces the same grid (existing theme-show tests cover this — keep them green).
- **JS:** no unit test harness for Stimulus in the gem; the controller is a verbatim port. The integration test asserts the `data-controller="design--dropdown"` / `data-action` / `data-…-target="menu"` wiring is present in the rendered HTML.
- **Locale parity:** `test/i18n/locale_parity_test.rb` stays green if any key is added.

## Risks

- **Eager-loaded Stimulus:** `eagerLoadControllersFrom("design-controllers", …)` picks up the new file automatically in apps that build the engine's JS (book_design, book_write). No registration needed, but the controller must live at exactly `app/javascript/design-controllers/design/dropdown_controller.js` to resolve as `design--dropdown`. Verify the rendered `data-controller` namespace matches.
- **`doc_type_label` move:** promoting it to `Base` and changing its arg from `dd` to `doc_type` touches the one `themes/show.rb` call site — update it in the same change or theme-show breaks. (Covered by existing theme-show tests.)
- **Switcher set divergence from book_design (Decision 3):** intentional; documented. If a cover-panel design ever needs editing, it's reached another way (out of scope).
- **Cosmetic only:** no model schema change, no migration, no host change; book_write/book_design get the toolbar automatically on next gem bump.

## Out of scope (later / not now)

book_design's full-height side-by-side editor layout and synchronous preview-on-load (the gem keeps its stacked + lazy preview), editing cover-panel doc designs from the studio, paragraph-style/style-browser work (#4), and retiring book_design's own `Pages::DocumentDesigns::*` (#6).
