# Paragraph-Styles: Style Browser + Form Parity — Design Spec (Sub-project #4)

**Date:** 2026-06-24
**Status:** Approved (brainstorm) — pending spec review
**Repo:** `design` gem only. book_design + book_write inherit. The browser is built so book_design can **retire its own** `StyleBrowserController` + `Pages::ParagraphStyles::Index` in #6 (one source of truth).
**Program context:** Sub-project **#4** of "converge the design studio onto book_design's UI." #0 (shell + host-action registry), #1 (themes), #2 (paper-sizes), #3 (document-designs toolbar) shipped. This ports book_design's **style browser** into the gem and brings the gem's **paragraph-style edit form** to feature-parity with book_design's. Later: #5 table styles, #6 retire book_design `Pages::*`.

**Guiding principle (from the user):** *one source of truth — do not diverge from book_design.* The gem becomes the canonical UI; where a book_design feature depends on a host-only service (per-row PDF links), expose it through the **#0 host-action registry** rather than dropping or diverging.

---

## Goal

Two pieces, one sub-project:

- **A. Style browser** — a global, all-themes, cascade-filtered (Theme → Size → Doc-type → Style-name) sortable table of every paragraph style across the hierarchy (theme base / paper-size / doc-design overrides), with an "override" badge — a verbatim structural port of book_design's `/style_browser`, mounted at `/design/style_browser`, reached from the gem's themes index. Becomes the canonical browser (#6 retires book_design's).
- **B. Paragraph-style form parity** — bring the gem's existing style-edit form up to book_design's feature set so it fully supersedes book_design's: the `vertical_align` field (table cells), an optional left-side live-preview pane (doc-design level), and a styled error block.

## Problem

- **Browser:** the gem has **no** style browser. book_design's `StyleBrowserController` + `Pages::ParagraphStyles::Index` is the only place to see/compare all paragraph styles across themes/sizes/doc-types at once. Its data pipeline (`build_style_rows`, `filtered_designs`) uses **only gem models** (`DocumentDesign#merged_paragraph_styles`, `#paragraph_styles`, `dd.theme`, `dd.paper_size`) — the lone host-only dependency is the per-row PDF link (`Rails.root.join("public", theme, size, doc_type, style, "output.pdf")` + `File.exist?`), produced by book_design's batch PDF export.
- **Form:** the gem's paragraph-style form (`Design::Views::ParagraphStyles::Form`/`Panel`/`Fields`, 3 level-controllers + the `DocumentDesignEditing` concern) is functional and arguably better-structured than book_design's inline-helper form, but lacks: the `vertical_align` field (gem model **already validates** it; form/params don't expose it), book_design's left-side live preview during editing, and book_design's `Alert`-style error block.

## Key findings (from exploration)

- **Host-action registry** (`lib/design/action_registry.rb`): `actions.for(slot, &block)` stores a block per slot symbol; `Base#render_host_actions(slot, context=nil)` resolves it and `helpers.instance_exec(context, &block)` → renders the returned descriptors. **Generic** — supports a new `:style_browser_row` slot called **per row** with the row as context. book_design registers its PDF-link descriptor there; book_write registers nothing.
- **book_design browser** (`style_browser_controller.rb`): `@themes = Design::Theme.all.order(:name)`; cascading params `theme`/`size`/`doc_type`/`style_name`, each validated against the computed option lists; `build_style_rows` → for a selected doc_type: every `dd.merged_paragraph_styles` row marked `is_override` via `dd.paragraph_styles` names; for "all doc types": base styles once per `[theme,size]` (deduped) + overrides per doc_type; sorted by `[theme_name, size_name, doc_type.to_s, style.name]`. `filtered_designs` eager-loads `:paragraph_styles, paper_size: { theme: :base_paragraph_styles }`. The `auto_submit` Stimulus controller is one method: `submit() { this.element.requestSubmit() }`.
- **`RubyUI::Alert` does NOT exist** in the gem (`app/components/ruby_ui/` = badge, button, card, tabs only). Use a **styled `<div>`** (the gem already renders errors as a plain div) — approved.
- **`paragraph_style_params` is duplicated** across `paragraph_styles_controller.rb:50`, `base_paragraph_styles_controller.rb:44`, `theme_paragraph_styles_controller.rb:38`, and `concerns/design/document_design_editing.rb:106`. Adding `vertical_align` touches all four (DRY opportunity — see Decision 7).
- **`vertical_align`** is a `Design::ParagraphStyle` column the model already validates; table-cell style names are `table_heading_cell` / `table_body_cell` (the family that should show the field).
- **Existing Stimulus** to reuse: `design--panel-autosave` (form autosave), `design--live-preview` (regenerates preview on input — used by `DocumentDesigns::PropertiesPanel`), plus color/border/corner editors. Browser cascade needs a new `design--auto-submit`.

## Decisions

| # | Decision |
|---|----------|
| 1 | **Port the browser verbatim (structurally).** New `Design::StyleBrowserController#index` at `/design/style_browser` + `Design::Views::ParagraphStyles::Browser` component. Global (all themes), four cascading auto-submitting filters, the sortable table with the override badge. Matches book_design so it can replace it in #6. |
| 2 | **Drop only the host-only `pdf_exists`** from the ported pipeline. The gem's row hash carries **objects** (`theme`, `paper_size`, `document_design` (nil for base rows), `style`, `is_override`, `doc_type`) — enough to render names AND build edit URLs. No `pdf_path`/`File.exist?` in the gem. |
| 3 | **PDF (and any host-only) links → per-row host-action slot.** The browser's actions cell calls `render_host_actions(:style_browser_row, row)`. book_design registers a block returning its `output.pdf` descriptor; book_write/gem render nothing there. |
| 4 | **Gem-native per-row "Edit" link** (additive; book_design can adopt it). Resolves to the style's level: override row → `edit_theme_paper_size_document_design_paragraph_style_path(theme, ps, dd, style)`; base row → by `style.styleable` type (Theme → `edit_theme_theme_paragraph_style_path`; PaperSize → `edit_theme_paper_size_base_paragraph_style_path`). |
| 5 | **`design--auto-submit` Stimulus controller** (verbatim port: `submit(){ this.element.requestSubmit() }`); the four filter `<select>`s submit the GET form on `change`. |
| 6 | **Entry point:** a gem-native link to the browser on the themes index (#1) (e.g. a "스타일 브라우저 / Style browser" link in the index header). It's a gem route — no host action needed. |
| 7 | **Form parity:** add `vertical_align` (select top/middle/bottom) to the `Fields` component, **rendered only for table-cell styles** (`table_heading_cell`/`table_body_cell`), and permit it in the paragraph-style params. **DRY the four duplicated permit lists** into one shared list (a constant/concern) and add `vertical_align` once. (Confirm the four lists are equivalent first; if a level legitimately permits less, keep that level's narrower list.) |
| 8 | **Optional live-preview pane** on the **doc-design-level** edit only (the level bound to a single `DocumentDesign` for `PreviewService`); reuse the existing preview turbo-frame + `design--live-preview`. Off for theme/paper-size-level edits (no single doc design to render). |
| 9 | **Errors via a styled `<div>`**, not `RubyUI::Alert` (doesn't exist). Match book_design's Alert look with utilities. Minimal — the gem already uses an error div. |

## Design

### A. Style browser (gem)

- **`Design::StyleBrowserController` (new):** `index` mirrors book_design's — load `@themes`, validate cascading params, `build_style_rows` (gem-model pipeline, no PDF), compute `@style_names`, filter by selected style, render the component. The pipeline ports as-is minus `pdf_exists`; rows carry objects (Decision 2).
- **`Design::Views::ParagraphStyles::Browser` (new):** renders inside `shell(...)`. A GET filter form (four `<select>`s: Theme/Size/Doc-type/Style-name, each `data-action="change->design--auto-submit#submit"`, the form `data-controller="design--auto-submit"`), then the sortable table. Columns mirror book_design (Name, Korean, Theme, Size, Doc-type [italic "all" for base / "override" badge], Font, Size, Color swatch, Fill, Border) **plus** an Actions column = the gem-native **Edit** link (Decision 4) + `render_host_actions(:style_browser_row, row)` (Decision 3). Explicit slate/blue utilities; the override badge via `RubyUI::Badge`.
- **Routes:** `get "style_browser", to: "style_browser#index", as: :style_browser` in the engine routes.
- **Entry point:** a link to `style_browser_path` on `Design::Views::Themes::Index`.

### B. Paragraph-style form parity (gem)

- **`Fields` component:** add a `vertical_align` `<select>` (top/middle/bottom, i18n labels), rendered only when the style name ∈ `%w[table_heading_cell table_body_cell]`. New i18n keys.
- **Params:** add `:vertical_align` to the shared paragraph-style permit list (Decision 7).
- **Live-preview pane:** the doc-design-level `Form`/`Panel` optionally renders the existing preview turbo-frame beside the form (reuse `DocumentDesigns` preview + `design--live-preview`); gated to the doc-design level.
- **Errors:** keep/полish the styled error `<div>`.

### i18n (gem, ko + en only)

Browser: column headers + filter labels + "override"/"all" + "Style browser" nav label + any empty-state. Form: `vertical_align` label + top/middle/bottom options. Identical keysets (parity test).

## Testing (Minitest)

- **Browser controller (integration):** no params → renders all themes' rows; selecting a theme narrows sizes/doc-types/rows; a doc_type filter shows overrides with the badge and base styles appropriately; a base style row's Edit link resolves to the theme- or paper-size-level edit path (per `styleable`); an override row's Edit link resolves to the doc-design-level path; the `:style_browser_row` host slot renders a descriptor when a test block is registered and nothing when not; cascade selects carry `design--auto-submit` wiring.
- **`build_style_rows` logic:** base-vs-override partitioning + the all-doc-types dedupe + sort order, asserted on a small fixture set.
- **Form parity:** `vertical_align` select appears for a `table_body_cell` style and is absent for `body`; updating it round-trips (persisted); the doc-design-level form renders the preview pane and the theme-level form does not.
- **Locale parity:** `test/i18n/locale_parity_test.rb` green.

## Risks

- **Browser perf (global, all themes):** `build_style_rows` over all themes × sizes × doc-types × merged styles can be large. book_design accepts this (it's a catalog/diagnostic tool); `filtered_designs` eager-loads associations to avoid N+1. Match book_design now; pagination/scoping is a deferred follow-up if needed. The cascade filters narrow it in practice.
- **Per-row host actions:** `render_host_actions(:style_browser_row, row)` resolves the block per row — fine for a registry lookup + `instance_exec`; book_design returns a single PDF descriptor. Keep the descriptor cheap.
- **Edit-URL resolution for base rows** depends on `style.styleable` being a Theme vs PaperSize; verify both map to existing edit routes (`theme_paragraph_styles` / `base_paragraph_styles`). If a merged base style's `styleable` is unexpectedly nil/other, fall back to no Edit link for that row.
- **`paragraph_style_params` DRY:** only merge the four permit lists if they're genuinely equivalent; a wrong merge could over/under-permit at a level. Compare first (Decision 7).
- **No `RubyUI::Alert`:** styled div only; no new RubyUI component (smaller surface, approved).

## Out of scope (later)

book_design's host-only PDF batch export itself (stays in book_design; surfaced via the registry), table styles (#5), retiring book_design's `StyleBrowserController` + `Pages::ParagraphStyles::*` (#6), browser pagination/async, and the side-by-side full-height editor layout (#3 kept the gem's stacked layout).
