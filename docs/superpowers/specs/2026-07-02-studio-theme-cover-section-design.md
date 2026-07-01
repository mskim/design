# Studio Theme Page — Book-Cover Section

**Date:** 2026-07-02
**Status:** Approved (design)
**Part of:** Sub-project A (cover image_opacity + logo theme fields). This surfaces the cover doc-type editors so the new authoring UI is reachable. Same branch: `feat-cover-image-opacity-logo-theme`.

## Goal

Add a **Book-cover section** to the design-gem studio theme page (`/design/themes/:id`) listing the cover doc-types (front_page, back_page, seneca, front_wing, back_wing) with preview + Edit links — so a designer can navigate to the cover document-design editors (where the new image_opacity/logo controls live). Today cover doc-types are excluded from the theme page and reachable only by direct URL.

## Current State (verified)

- `Design::ThemesController#show` sets `@document_designs = interior_document_designs(@selected_paper_size)` → `Design::DocumentDesign.interior_for(paper_size)` = `by_reading_order(paper_size.document_designs.where.not(doc_type: COVER_PANEL_TYPES))`. **Cover doc-types are filtered out.** `@document_designs` feeds only the `doc_grid` in the Show component (verify no other consumer before widening it).
- `Design::DocumentDesign.grouped_by_matter(designs)` returns `{ frontmatter:, bodymatter:, rearmatter:, other: }` — `ordered = by_reading_order(designs)` then `select`/`reject` by the `FRONTMATTER`/`BODYMATTER`/`REARMATTER` constants. `by_reading_order` sorts by `DOC_TYPE_ORDER` (interior types only — cover types have no defined order there). `other` = reject(frontmatter+bodymatter+rearmatter) and is NOT rendered.
- `Design::Views::Themes::Show` (`app/components/design/views/themes/show.rb`): `MATTER_SECTIONS = [[:frontmatter, "design.themes.frontmatter"], [:bodymatter, "design.themes.bodymatter"], [:rearmatter, "design.themes.rearmatter"]]`. `doc_grid` calls `grouped_by_matter(@document_designs)` and renders each `MATTER_SECTIONS` group via `matter_section(key, designs, index)` → `doc_card(dd, index)` (preview thumbnail + an Edit link `edit_theme_paper_size_document_design_path`, gated on `@theme.editable_by?`). `doc_card` already works for ANY doc-type (cover dds have working previews via `preview_jpg_theme_paper_size_document_design_path`).
- **Cover document_designs exist** for every paper_size (all 5 cover types — confirmed in the dev DB). `COVER_PANEL_TYPES = %w[front_page back_page seneca front_wing back_wing]`.

## Design

Reuse the existing `matter_section`/`doc_card` machinery by adding a `cover` matter group, rendered **last** (after rearmatter).

### C1 — `grouped_by_matter` gains a `cover` bucket (model)

`app/models/design/document_design.rb`: add to the returned hash:
```ruby
cover: designs.select { |dd| COVER_PANEL_TYPES.include?(dd.doc_type) }
              .sort_by { |dd| COVER_PANEL_TYPES.index(dd.doc_type) },
```
and update `other:` to ALSO exclude cover types (so a cover dd never lands in both `cover` and `other`): `reject { |dd| (FRONTMATTER + BODYMATTER + REARMATTER + COVER_PANEL_TYPES).include?(dd.doc_type) }`. Cover ordering is by `COVER_PANEL_TYPES` index (NOT `by_reading_order`, which doesn't know cover types).

### C2 — `themes#show` passes all document_designs (controller)

`app/controllers/design/themes_controller.rb#show`: change `@document_designs` to include cover types. Simplest: pass all of the paper size's document_designs (e.g. `@selected_paper_size.document_designs.to_a`) — `grouped_by_matter` partitions them, and the existing frontmatter/bodymatter/rearmatter sections filter by their own type lists so they're unaffected. Keep `interior_for`/`interior_document_designs` if used elsewhere; only the `show` assignment changes. Verify `@document_designs` has no other consumer in the Show component that assumes interior-only.

### C3 — `Themes::Show` renders the cover section last (component)

`app/components/design/views/themes/show.rb`: append `[:cover, "design.themes.cover"]` to `MATTER_SECTIONS` (LAST, after rearmatter). No other change — `doc_grid`'s loop + `matter_section` + `doc_card` handle it. The Edit link + preview already work for cover dds.

### C4 — i18n

`config/locales/ko.yml` + `en.yml` under `design.themes`: `cover: "표지"` (ko) / `cover: "Book cover"` (en). Merge into the existing `design.themes` map.

## Edge Cases

- A paper_size missing some cover dds → the `cover` bucket just has fewer cards (no crash; `select` yields what exists).
- `editable_by?` false → the Edit link is hidden (existing `doc_card` behavior), preview still shows. Consistent with interior sections.
- `other` bucket: still unrendered; now correctly excludes cover types too (cosmetic — prevents double-listing if `other` is ever rendered).

## Testing (design gem, Minitest)

- **Model** (`document_design_test.rb`): `grouped_by_matter([...cover + interior...])[:cover]` returns the cover dds ordered by `COVER_PANEL_TYPES` (front_page first, back_wing last); a cover dd is NOT in `[:other]`.
- **Controller/render** (`themes_*` test — mirror the existing theme-show test's setup: `sign_in :david`, owned theme, `design.` route prefix): `get design.theme_path(theme)` (or the show route) → response includes a "표지"/cover section AND an Edit link to a cover doc-type (`assert_select "a[href=?]", design.edit_theme_paper_size_document_design_path(theme, ps, front_page_dd)`).

## Constraints

- design gem only (no book_design, no export, no book_write). i18n ko + en. Stage explicit paths (unrelated Gemfile.lock).

## Success Criteria

1. The theme page shows a "표지 / Book cover" section (last, after rearmatter) with the 5 cover doc-types, ordered front_page→back_page→seneca→front_wing→back_wing, each with a preview + Edit link.
2. A designer can click through to a cover document-design editor (reaching the image_opacity/logo controls from Sub-project A).
3. Existing frontmatter/bodymatter/rearmatter sections unchanged; gem tests pass.
