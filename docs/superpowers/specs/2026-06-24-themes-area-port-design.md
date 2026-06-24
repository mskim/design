# Themes Area Port — Design Spec (Sub-project #1)

**Date:** 2026-06-24
**Status:** Approved (brainstorm) — pending spec review
**Repo:** `design` gem (primary). `book_design` drops one registered action (initializer).
**Program context:** Sub-project **#1** of "converge the design studio onto book_design's UI." #0 (shell + host-action registry) is shipped. This ports book_design's **Themes area** content into the gem so the `/design` studio's theme index/show/forms match book_design. Later: #2 paper-sizes, #3 document-designs, #4 paragraph-styles/style-browser, #5 table-styles, #6 retire book_design `Pages::*`.

---

## Goal

Make the gem studio's Themes area look and work like book_design's: a flat responsive grid of rich theme cards with **real (generated) previews**, a theme show page that **groups document designs into Frontmatter / Bodymatter / Rearmatter**, and **theme create/edit** (which the gem lacks entirely today). Host-only tools (palette-generate, import, generate-PDFs, export) stay host services, surfaced as buttons through the #0 action registry.

## Problem

The gem's `Design::Views::Themes::*` are sparse vs book_design's `Pages::Themes::*`: (a) the index is a 2-column System/Custom split with a basic card that **assumes the preview JPG already exists** (so it shows a "미리보기 없음" placeholder or a broken image); (b) the show page is a flat doc grid with no reading-order grouping; (c) the gem has **no theme form** at all — only clone/rename/destroy, no `new`/`create`/`edit`. book_design's versions render generated previews, group by matter, and offer full create/edit.

## Key findings (from exploration)

- **Preview:** `Design::PreviewService` lives in the gem (`app/services/design/preview_service.rb`); `.generate` does PDF→JPG and returns `{ success:, jpg_path:, … }` with a tmp cache keyed on `DocumentDesign#updated_at`. book_design **calls `.generate` before** rendering the `<img src=preview_jpg_…_path(…, t: Time.now.to_i)>`; the gem's card renders the `<img>` without generating first. This is why studio previews are missing/broken.
- **Index:** gem `themes/index.rb` = 2-col System/Custom, `chapter_preview` (no generate), counts only. book_design `pages/themes/index.rb` = responsive `grid-cols-2…lg:grid-cols-6`, `RubyUI::Card`, generate-first preview, paper-size badges + body font.
- **Show:** gem `themes/show.rb` = paper-size tabs + turbo-frame + flat 5-col grid (now via `Design::DocumentDesign.by_reading_order`). book_design `pages/themes/show.rb` = grouped by Frontmatter/Bodymatter/Rearmatter, pre-populated previews, plus table-styles + other-sizes (out of scope here).
- **Form/CRUD:** gem `Design::ThemesController` has only `index/show/update(rename)/destroy/clone/generate_sizes`; engine routes lack `new/create/edit`. book_design `Pages::Themes::Form` collects name/description/locale + body-font/body-size/heading-font; `ThemesController#new/create/edit/update`. The fields are model attributes (`Design::Theme`: `name, description, locale, base_body_font, base_body_font_size, base_heading_font`, with `AVAILABLE_FONTS`) — **pure, gem-movable**.
- **`by_reading_order` + groups:** the gem has `Design::DocumentDesign::DOC_TYPE_ORDER` + `by_reading_order` (added in a prior fix). It does **not** yet have the three matter-group constants; book_design defines `FRONTMATTER/BODYMATTER/REARMATTER` locally.
- **Host-only (stay host, surfaced via #0 registry):** `generate` (ThemeGeneratorService + PALETTES), `import`/`import_book_design` (ThemeImportService/BookDesignImportService), `generate_style_pdfs` (StylePdfBatchService), `export_theme_db` (ThemeDbExportService). book_design already registers Export / Generate-PDFs / Generate / Import / Style-browser / New-theme in its `:theme_show` / `:themes_index` slots.

## Decisions

| # | Decision |
|---|----------|
| 1 | **Index = flat responsive grid**, no System/Custom split — match book_design exactly. |
| 2 | **Generate-first previews** on the index card + show cards (call `PreviewService.generate`, render the JPG with a cache-buster). Empty themes render no preview strip. |
| 3 | **Show groups doc designs into Frontmatter / Bodymatter / Rearmatter** (match book_design); keep the paper-size tab selector + turbo-frame switching. |
| 4 | **Add theme create/edit to the gem** — `Form` + `new/create/edit/update` + routes. "New theme" and "Edit Theme" become **gem-native** buttons. |
| 5 | A gem-created theme is **metadata-only** (gets the gem's default table/cell styles, not the 34 named base styles — those come from host palette-generation). Real themes still come from **Clone** or host **Generate**. Accepted for parity with book_design's plain create. |
| 6 | **Host boundary unchanged** except book_design **drops "New theme"** from its `:themes_index` registration (gem provides it natively); Import / Generate / Style-browser / Export / Generate-PDFs stay registered. |
| 7 | **Perf of generate-on-render is a known follow-up** (a populated index does N PDF→JPG generations per load). Match book_design now; a caching/async pass is deferred (out of scope). |

## Design

### Components (gem)

- **`Design::Views::Themes::Index` (rewrite):** flat `grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4` of `RubyUI::Card`s. Each card: generate-first preview strip (see below), theme name, `base_body_font`, locale badge, paper-size badges (★ for default), doc-type count, and the per-theme actions (View, Clone, Rename, Delete — keeping the gem's existing inline clone/rename forms). A gem-native **"New theme"** link (→ `new_theme_path`) in the page header area, plus `render_host_actions(:themes_index)` for the host buttons.
- **`Design::Views::Themes::Show` (enrich):** keep `header_section` (name + editable badge + clone) and the `size_selector` paper-size tabs + turbo-frame. Replace the flat `doc_grid` with **grouped sections**: for the selected size's interior document designs, partition by the three matter groups and render a titled section per non-empty group (`Frontmatter`/`Bodymatter`/`Rearmatter`, localized), each a responsive grid of preview cards. Generate-first previews. Native **"Edit Theme"** button + `render_host_actions(:theme_show, @theme)`.
- **`Design::Views::Themes::Form` (new):** sections Identity (`name` required, `description` textarea, `locale` select ko/en/ja/zh) + Default Fonts (`base_body_font` select from `Design::Theme::AVAILABLE_FONTS`, `base_body_font_size` number, `base_heading_font` select). Submit → `themes_path` (POST) when new / `theme_path` (PATCH) when persisted; Cancel link. Render validation errors (`@theme.errors`).
- Index/Show/Form all render inside the #0 `shell(...)` (top bar + host-action slot).

### Generated-preview helper

A shared helper (e.g. on `Design::Views::Base` or a small concern) used by index + show cards:
```ruby
def theme_chapter_preview(theme)
  ps = theme.default_paper_size or return preview_empty
  dd = ps.document_designs.find_by(doc_type: "chapter") or return preview_empty
  result = Design::PreviewService.new(dd, paper_size: ps).generate
  return preview_empty unless result[:success]
  img(src: helpers.preview_jpg_theme_paper_size_document_design_path(theme, ps, dd, t: cache_buster), …)
end
```
`cache_buster` derives from `dd.updated_at.to_i` (stable per content, busts on change) rather than `Time.now` (which defeats browser caching every load) — a small improvement over book_design's `Time.now.to_i` that still matches behavior. The show grid generates per visible doc design similarly.

### Doc-type matter groups

Add to `Design::DocumentDesign` (next to `DOC_TYPE_ORDER`): `FRONTMATTER`, `BODYMATTER`, `REARMATTER` constants (mirroring book_design's grouping). A helper `self.grouped_by_matter(designs)` returns ordered `{ frontmatter: [...], bodymatter: [...], rearmatter: [...] }` (each already `by_reading_order`, unknowns appended to a trailing group or omitted). The show view renders a section per non-empty group.

### Controller + routes (gem)

`Design::ThemesController`: add `new` (build), `create` (save → redirect to show; on invalid → re-render Form 422), `edit` (render Form), and extend `update` to permit the full Form params (currently rename-only) while keeping the `editable_by?` authorization. Engine `config/routes.rb`: add `new`, `create`, `edit` to `resources :themes` (already has `index/show/update/destroy` + `clone`/`generate_sizes`).

### Host boundary (book_design)

`config/initializers/design.rb`: remove the `New theme` descriptor from the `:themes_index` registration (the gem renders it natively). Keep Import / Generate / Style-browser. No other host change (book_design's own `/themes` host pages + its `ThemesController#new/create` remain until #6).

## Testing

- **Component:** index renders a flat grid of cards with a generated preview `<img>` when the theme has a chapter doc (stub `PreviewService.generate` → `{success: true, …}`) and no strip when empty; renders name/font/badges; the gem-native "New theme" link present. Show renders the three matter sections in order with the right doc designs in each (stub previews). Form renders all fields + a validation error.
- **Controller/integration:** `new` renders the form; `create` with valid params makes a theme + redirects to show; invalid → 422 + errors; `edit`/`update` round-trip the font/locale fields; `update` still enforces `editable_by?`.
- **Preview helper:** `theme_chapter_preview` calls `generate` and only emits the `<img>` on success; cache-buster derives from `updated_at`.
- **Grouping:** `grouped_by_matter` partitions correctly and orders by `by_reading_order`.
- Minitest only; mirror existing gem component/controller test patterns; stub `PreviewService.generate` so tests don't shell out to PDF rendering.

## Risks

- **Generate-on-render perf** (Decision 7) — N PDF→JPG per index load. Mitigation: `updated_at`-keyed cache in `PreviewService` already avoids re-rendering unchanged designs; the cache-buster keys on `updated_at` so the browser caches too; full async/batch caching is a deferred follow-up.
- **Metadata-only created themes** (Decision 5) — a gem-created theme has no 34 base styles, so its previews/styles are sparse until cloned-from or host-generated. Matches book_design's plain create; documented in the Form.
- **PreviewService in tests** — must be stubbed (it shells out to doc_processor_rb + ImageMagick). All preview-touching tests stub `.generate`.
- **Styling** — book_design's card/badge/section classes must compile in the gem's scoped build; they're explicit utilities + RubyUI under `app/components/**` (already globbed). The intentionally-dead token classes no-op identically (no token authoring).
- **book_write** — gets the richer studio automatically (renders the gem); registers no actions → no host buttons. The native "New theme"/"Edit" buttons appear (gem routes) and work (pure CRUD). Additive; no migration.

## Out of scope (later sub-projects)

Table styles + the other-sizes collapsible on the show page (#5 / later), retiring book_design's `Pages::Themes::*` and its `ThemesController#new/create/edit` (#6), async/cached preview generation, and any host-only flow internals (generate/import/pdf/export stay host pages the registry buttons link to).
