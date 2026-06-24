# Gem-Native Table-Style Preview Rendering — Design Spec

**Date:** 2026-06-25
**Status:** Approved (brainstorm) — pending spec review
**Repos:** **design gem** (port the renderer + rewire) and **book_design** (delete its now-redundant copy + hook). No book_write change (it inherits the gem).
**Context:** #5 shipped the table-styles editor but rendered the preview pane through a **host hook** (`Design.config.table_style_preview`) because `SingleTablePdf` was thought to be book_design-only. It isn't — it's a thin wrapper over `doc_processor_rb`'s `InlineTable`, and the gem already depends on `doc_processor_rb` + `hexapdf` (for `PreviewService`). So the gem can render table previews itself. This makes table previews work in **every** host (book_design, local book_write, the deployed Docker server) with **zero host registration**, retires #5's placeholder/host-hook stopgap, and is the prerequisite for the theme-sync **Import** feature to regenerate table previews.

## Goal

Move table-style preview rendering **into the gem** so `Design::TableStylePreviewsController` (and the editor/theme-show previews) render natively via `doc_processor_rb`. `Design.config.table_style_preview` becomes an **optional override** (default = gem-native). book_design deletes its 5 preview services + the hook registration. Every host's studio shows real table previews; the theme-sync import regenerates them by calling the gem service.

## Decisions

| # | Decision |
|---|----------|
| 1 | **Port the 5-service pipeline into the gem** under `Design::`: `TableStylePreviewService` (orchestrator), `TableStyleResolver`, `SingleTablePdf`, `TableStylePreviewSample`, `HexToCmyk`. Faithful ports of book_design's (`app/services/*`). |
| 2 | **DRY the PDF→JPG step:** extract the identical `convert_pdf_to_jpg` from `PreviewService` into a shared `Design::PdfToJpg.convert(pdf_path, jpg_path, dpi:)`; both `PreviewService` and `TableStylePreviewService` use it. |
| 3 | **Hook becomes an optional override.** `TableStylePreviewsController#show`: `blob = Design.config.table_style_preview ? hook.call(theme, ts) : Design::TableStylePreviewService.call(theme, ts)`. No more `head :not_found` for an unset hook. **Render-error behavior is explicit:** `show` rescues `StandardError` from the service/hook → log + `head :unprocessable_entity` (the `<img>`'s `onerror`/`alt` then degrades gracefully), so one bad table style never 500s the grid. `ActiveRecord::RecordNotFound` → `head :not_found` (unchanged). |
| 4 | **Components always render the preview `<img>`.** Drop the `if Design.config.table_style_preview` gates in `TableStyles::Edit` (preview pane, `edit.rb:23`) and `Themes::Show` (table-style grid, `show.rb:181`) — render the `<img>` unconditionally. **Delete the `else`-branch placeholder markup** in both; if `design.table_styles.no_preview` (gem locales) becomes unused after that, remove the key. Keep only the `<img alt=…>`/`onerror` as the degrade path (paired with Decision 3's rescue). |
| 5 | **book_design deletes its copy** (convergence — one source of truth): remove `app/services/{table_style_preview_renderer,table_style_resolver,single_table_pdf,table_style_preview_sample,hex_to_cmyk}.rb`, the two tests (`test/services/{table_style_resolver,hex_to_cmyk}_test.rb`), and the `c.table_style_preview = …` line in `config/initializers/design.rb`. (Confirmed: those + the hook are the only references.) |
| 6 | **Caching deferred.** Render on demand (matches book_design + #5); a fingerprint cache for the N-per-grid-load case is a later perf pass (consistent with #1/#5). |

## Key findings (from exploration)

- **The 5 book_design services** (`app/services/`): `TableStylePreviewRenderer` (→ resolver → SingleTablePdf → Vips, returns a JPEG blob); `TableStyleResolver` (`TableStyle` + theme `base_paragraph_styles` for `table_heading_cell`/`table_body_cell` → a `style_hash`, colors via `HexToCmyk`); `SingleTablePdf` (`require "hexapdf"` + `DocProcessorRb::Layout::InlineTable.new(rows:, width:, style_hash:).measure` + `draw_pdf(canvas, x:, y:)` on a 595.28×200 page); `TableStylePreviewSample::SAMPLE` (a 1-header/3-body Region/Population/Area table); `HexToCmyk` (~20-line hex→CMYK).
- **Deps are present but transitive:** `hexapdf (1.9.1)` resolves via `doc_processor_rb`'s gemspec and `ruby-vips (2.3.0)` via `image_processing` (gem-root Gemfile) — `PreviewService` already `require`s both. `design.gemspec` declares neither directly. Since `SingleTablePdf` adds a **first-party** `require "hexapdf"` in gem app code, **add `spec.add_dependency "hexapdf"` to `design.gemspec`** (declare the dependency the gem now relies on directly; ruby-vips stays transitive via image_processing, as `PreviewService` already does). No new *installed* gem — just an honest contract.
- **`PreviewService#convert_pdf_to_jpg`** is byte-identical to `TableStylePreviewRenderer#convert_pdf_to_jpg` (read buffer → flatten alpha to white → `jpegsave Q: 85`, DPI 150) — extract once (Decision 2).
- **Controller (#5):** `TableStylePreviewsController#show` currently `blob = Design.config.table_style_preview&.call(...)` → `head :not_found unless blob`. Rewire per Decision 3.
- **Components (#5):** `table_styles/edit.rb:23` and `themes/show.rb:181` gate the `<img>`/`turbo_frame` on `Design.config.table_style_preview`. Rewire per Decision 4.
- **book_design references** to the 5 services: only `design.rb:17` (the hook) + `test/services/{table_style_resolver,hex_to_cmyk}_test.rb`. No app code else. Safe to delete (Decision 5).
- **doc_processor_rb `InlineTable` API:** `new(rows:, width:, style_hash:)`, `measure`, `draw_pdf(canvas, x:, y:)`. The gem's pinned `doc_processor_rb` must expose this (book_design uses it via the same dependency). Verify against the gem's `doc_processor_rb`.

## Design

### New gem services (`app/services/design/`)
- **`Design::TableStylePreviewService.call(theme, table_style) → jpg_blob`** — orchestrator: `style_hash = Design::TableStyleResolver.call(theme, table_style)`; write a 1-page PDF via `Design::SingleTablePdf.write(tmp_pdf, rows: Design::TableStylePreviewSample::SAMPLE[:rows], style_hash:)`; `Design::PdfToJpg.convert(tmp_pdf, tmp_jpg, dpi: 150)`; `File.binread(tmp_jpg)`. Tempfiles cleaned in `ensure`.
- **`Design::TableStyleResolver`**, **`Design::SingleTablePdf`**, **`Design::TableStylePreviewSample`**, **`Design::HexToCmyk`** — ports (namespaced under `Design::`; `TableStyleResolver` reads `theme.base_paragraph_styles.find_by(name: "table_heading_cell"/"table_body_cell")`).
- **`Design::PdfToJpg.convert(pdf_path, jpg_path, dpi: 150)`** — the extracted shared Vips step; `PreviewService#convert_pdf_to_jpg` is refactored to call it (no behavior change).

### Rewire (gem)
- `TableStylePreviewsController#show` — Decision 3 (gem-native default; hook override; rescue → `head :unprocessable_entity`).
- `TableStyles::Edit#preview_pane` + `Themes::Show#table_style_card` — Decision 4 (always render the `<img>`; delete the placeholder else-branch).
- `design.gemspec` — add `spec.add_dependency "hexapdf"` (first-party `require` now lives in `SingleTablePdf`).

### book_design (delete)
- Remove the 5 services + 2 tests + the `c.table_style_preview` registration (Decision 5). Verify the full suite + eager-load stay green (book_design's table previews now come from the gem).

## Testing

**Gem (Minitest):**
- `Design::HexToCmyk` — port book_design's cases (`#ffffff → [0,0,0,0]`, `#000000 → [0,0,0,100]`, `#cccccc → [0,0,0,20]`).
- `Design::TableStyleResolver` — port book_design's test (style_hash keys/values, CMYK conversion, header/body cell paragraph hashes).
- `Design::TableStylePreviewService.call(theme, ts)` — returns a non-empty `image/jpeg` blob (real render: `doc_processor_rb` InlineTable + Vips). Use a seeded theme + one of its table styles. (Env must have Vips/doc_processor — the gem's `PreviewService` tests already require this.)
- Controller `show`: **default (no hook)** → `200 image/jpeg`, non-empty; **with a hook registered** → uses the hook (assert the override path, e.g. a stub blob); **service raises** → `head :unprocessable_entity` (stub the service to raise; assert no 500). For the hook test, **save the original `Design.config.table_style_preview` and restore it in `ensure`** (not just nil it) — this mutates a shared singleton, so save/restore + keep this test off parallel workers that share config (mirrors the known doc_processor_rb/global-state caveat).
- Components: `TableStyles::Edit` renders `turbo-frame#preview_frame img` and `Themes::Show` renders the table-style card `<img>` **with no hook registered** (the old `else`-branch placeholder is gone — assert the placeholder markup is absent).
- `Design::PdfToJpg.convert` round-trips a tiny PDF → JPEG (or covered transitively by the service test).

**book_design (Minitest):** after deletion — the existing `StudioCutoverTest` table-preview assertion (#6) should now pass **without** registering the hook (gem-native); update it to drop the hook setup. Full suite + `Rails.application.eager_load!` green (no dangling refs to the deleted services).

## Risks

- **`doc_processor_rb` InlineTable API drift** — the port calls `InlineTable.new(rows:, width:, style_hash:)` / `measure` / `draw_pdf`. If the gem's pinned `doc_processor_rb` differs from book_design's, adjust. Mitigation: both apps use the same `doc_processor_rb` dependency; verify the method signatures during Task 1.
- **Vips / rendering in CI** — same env requirement as the gem's existing `PreviewService` tests; if Vips is absent the service test fails for an env reason, not the change.
- **Perf (N renders per grid load)** — deferred (Decision 6); no worse than today (book_design rendered the same way via the hook).
- **book_design deletion** — verified the 5 services are referenced only by the hook + 2 tests; the plan re-greps + eager-loads before deleting.
- **Override semantics** — a host that still registers `table_style_preview` keeps full control (override wins); book_write/the server register nothing → gem-native. No behavior loss.

## Out of scope

Preview caching (Decision 6 — later perf pass), the theme-sync export/import buttons (separate feature; this is its prerequisite — the import will call `Design::TableStylePreviewService` to warm table previews), and any change to doc-design/`PreviewService` rendering beyond the `convert_pdf_to_jpg` extraction.
