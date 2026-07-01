# Cover image_opacity + Logo Positioning as Theme Fields (Sub-project A)

**Date:** 2026-07-02
**Status:** Approved (design)
**Principle:** design/content separation — the designer authors design ONCE in book_design; book_write edits content only. This moves the last per-cover style controls (image_opacity, logo positioning) into the theme so a designer sets them per cover doc-type.
**Predecessor:** cover-styles-from-theme (shipped) moved cover typography + heading layout to the theme via `CoverThemeStyles` (book_write).
**This is Sub-project A of 2:** A = theme carries + designer authors the fields (this spec, `design` gem + book_design). B = book_write consumes them + strips the image_opacity slider (separate cycle; depends on A).

## Goal

Let a designer set, **per cover doc-type**, a background-image `image_opacity` and **logo positioning** (`logo_width`, `logo_height`, `logo_position`, `logo_offset`) on `Design::DocumentDesign`, author them in the design-gem studio, and bake them into the theme SQLite DB. Outcome: shipped/edited themes carry these fields. No book_write change here (that's Sub-project B).

## Scope

**In:** new `design_document_designs` columns; `Design::DocumentDesign` model support + a `LOGO_POSITIONS` constant; studio authoring UI in the `PropertiesPanel` Layout tab (gated to cover doc-types / front_page); strong-params permit; `ThemeDbExportService` bakes the columns; ko+en i18n; re-bake shipped themes; tests.

**Out:** book_write consumption + stripping the image_opacity slider (Sub-project B); the pre-existing engine-panel opacity gap (front_page/seneca/wings don't apply background-image opacity — a doc_processor render feature); any change to the logo *image* attachment (that's book_write content).

## Field model (mirrors book_write's existing `page_layout` logo fields to keep Sub-project B trivial)

- `image_opacity` — integer 0–100, default 100. Background-image opacity for a cover panel. Applies to cover doc-types that can carry a background image (front_page, back_page, seneca, front_wing, back_wing).
- `logo_width` — decimal (mm). Logo box width.
- `logo_height` — decimal (mm). Logo box height.
- `logo_position` — string, one of `left` / `center` / `right` (matches book_write's `render_logo_element`, which aligns via `style[:align]`). Default `center` (or nil → book_write default).
- `logo_offset` — decimal (mm), default 0. Vertical offset.
- Logo fields are meaningful only for **front_page** (the logo image attaches to front_page in book_write). The columns exist on all rows but the authoring UI shows the logo section for front_page only.

## Current State (verified)

**`Design::DocumentDesign`** (`app/models/design/document_design.rb`; table `design_document_designs` in book_design `db/schema.rb`): ~42 columns incl. layout fields already designer-editable (`heading_v_align`, `text_box_anchor_position`, `text_box_grid_width/height`, `page_bg_color`, `heading_bg_*`, `has_document_cover`, `cover_type`). Constants: `COVER_PANEL_TYPES = %w[front_page back_page seneca front_wing back_wing]`, `SINGLE_PAGE_TYPES`, `MULTI_PAGE_TYPES`, `DOC_TYPE_STYLE_FAMILIES`, `DEFAULT_HEADING_ELEMENTS`. Has NO image_opacity or logo columns.

**Studio editing** (Phlex components):
- Controller `Design::DocumentDesignsController#update` (`app/controllers/design/document_designs_controller.rb`) persists `document_design_params` then calls `Design::ThemeDbExportService.new(@theme).export!` (re-bake on save).
- Strong params: `Design::DocumentDesignEditing#document_design_params` (`app/controllers/concerns/design/document_design_editing.rb`, ~line 220) — the permit list of editable attrs.
- Form: `app/components/design/views/document_designs/properties_panel.rb` (Phlex, ~579 lines). **Layout tab** (`render_layout_tab`, ~lines 82–103) already renders text-box position (anchor + grid), page bg, document-cover sections via `group_box`/`number_field`/`select_field`/`checkbox_field` helpers (from `app/components/design/views/field_groups.rb`). A `toc`-only conditional (`if @document_design.doc_type == "toc"`, ~line 89) is the pattern for doc-type-gated sections.

**Export** (`app/services/design/theme_db_export_service.rb`):
- `create_tables` — `CREATE TABLE document_designs (...)` (~lines 62–81): the column DDL.
- `insert_paper_sizes_and_designs` — `INSERT INTO document_designs (...) VALUES (...)` (~lines 143–161) with the column list.
- `document_design_values(dd)` (~lines 177–194): the per-row value tuple (booleans → 0/1, floats via `f()`, timestamps → iso8601).
- Baked DBs written under `Design.themes_dir` (system) or `.../user_<id>/` (user themes).

**Migrations:** book_design `db/migrate/` (the gem's tables were adopted into the host app's schema, migration `20260621000001_adopt_design_gem_tables.rb`). Current add-column pattern (post-adoption, correct table name): `20260622000001_add_toc_v_align_to_design_document_designs.rb` → `add_column :design_document_designs, :toc_v_align, :string`. (Older migrations like `20260308114043_add_text_box_position_to_document_designs.rb` predate the rename and use the unnamespaced `:document_designs` — do NOT copy that name.)

**Gem test schema:** the gem's tests do NOT run migrations — `test/test_helper.rb` `load`s `test/dummy/db/schema.rb` directly (a hand-maintained copy of the `design_*` tables). New columns must be hand-added there too (see C1).

**Tests** (Minitest, in the gem `test/`): model `test/models/design/document_design_test.rb`; controller `test/controllers/design/document_designs_edit_test.rb`; export `test/services/design/theme_db_export_service_test.rb` (opens the baked SQLite and asserts row column values — the `cover_type`/`toc_v_align` pattern).

## Components

### C1 — Migration (book_design) + gem dummy schema

New migration in `book_design/db/migrate/` (host app owns the gem's tables; follow the current pattern in `20260622000001_add_toc_v_align_to_design_document_designs.rb`, which uses the post-adoption table name `:design_document_designs`):
```ruby
add_column :design_document_designs, :image_opacity, :integer, default: 100
add_column :design_document_designs, :logo_width,    :decimal, precision: 6, scale: 2
add_column :design_document_designs, :logo_height,   :decimal, precision: 6, scale: 2
add_column :design_document_designs, :logo_position, :string
add_column :design_document_designs, :logo_offset,   :decimal, precision: 6, scale: 2, default: 0
```
Run `bin/rails db:migrate` in book_design; commit the updated `book_design/db/schema.rb`.

**CRITICAL — the gem's tests do NOT run migrations.** `design` gem `test/test_helper.rb` `load`s `test/dummy/db/schema.rb` directly (the dummy app has no migrations); that schema is a hand-maintained copy of the `design_*` tables (e.g. `toc_v_align` was hand-added there). So the book_design migration has **zero effect on gem tests**. This task MUST also **hand-edit `design` gem `test/dummy/db/schema.rb`** to add the 5 columns to the `design_document_designs` table block — otherwise every model/controller/export test fails with `no such column`. This is a mandatory, separate edit, not implied by the migration.

### C2 — `Design::DocumentDesign` (gem)

- Columns auto-load via ActiveRecord. Add `LOGO_POSITIONS = %w[left center right].freeze` for the select.
- Optional: an `image_opacity` reader guard (clamp/default 100 if nil) — but default is set at the DB, so minimal.
- No new validations required beyond an optional `inclusion` on `logo_position` (allow_nil).

### C3 — Studio authoring UI (gem)

- **Strong params** (`document_design_editing.rb`): permit `:image_opacity, :logo_width, :logo_height, :logo_position, :logo_offset`.
- **PropertiesPanel** (`properties_panel.rb`): in `render_layout_tab`, after the existing page-bg / cover sections, add:
  - `render_image_opacity_section` — a `group_box` with a `number_field` (0–100) for `image_opacity`; rendered only when `DocumentDesign::COVER_PANEL_TYPES.include?(@document_design.doc_type)`.
  - `render_logo_section` — a `group_box` with `number_field`s for `logo_width`/`logo_height`/`logo_offset` and a `select_field` for `logo_position` (`LOGO_POSITIONS`); rendered only when `@document_design.doc_type == "front_page"`.
  - Reuse `group_box`/`rows`/`number_field`/`select_field`/`disabled_attr` and the `design--live-preview` data-controller so edits live-preview like the other layout fields.
- **i18n:** add label keys under the design engine's locale (ko + en) — e.g. `design.properties_panel.image_opacity`, `.logo_width`, `.logo_height`, `.logo_position`, `.logo_offset`, and the logo_position option labels.

### C4 — `ThemeDbExportService` (gem)

- `create_tables`: add to the `document_designs` DDL: `image_opacity INTEGER DEFAULT 100, logo_width REAL, logo_height REAL, logo_position TEXT, logo_offset REAL DEFAULT 0`.
- `insert_paper_sizes_and_designs`: add the 5 columns to the `INSERT INTO document_designs (...)` column list, AND update the placeholder literal — the INSERT uses `VALUES (#{Array.new(38, "?").join(", ")})`, so change **`38` → `43`** (it's a hardcoded count, not per-column `?`s — easy to miss).
- `document_design_values`: append `dd.image_opacity, f(dd.logo_width), f(dd.logo_height), dd.logo_position, f(dd.logo_offset)` to the tuple (keep column↔value order aligned; book_write reads by name so downstream is order-independent).
- **Four coupled sites** must stay in sync: (1) CREATE TABLE DDL, (2) INSERT column list, (3) the `Array.new(N, "?")` placeholder count, (4) the `document_design_values` tuple.

### C5 — Re-bake shipped themes

After the export change, existing baked theme DBs are stale (lack the columns). Re-bake all themes so Sub-project B has data:
- Use the design gem's existing re-bake path (the same `ThemeDbExportService.export!` the controller calls) via a task/console for every `Design::Theme`, or the project's `design:refresh_all_theme_dbs`-style task if one exists on the design/book_design side. Document the exact command in the plan. (book_write's own `storage/themes/*.db` are separately regenerated by book_write's `design:refresh_all_theme_dbs` — note that Sub-project B / a re-bake covers book_write's copies.)

## Data Flow

```
Designer → studio DocumentDesign edit (cover doc-type)
  Layout tab: Image-opacity (cover panels) + Logo (front_page) controls
  → PATCH update → document_design_params permits image_opacity + logo_*
  → save design_document_designs
  → DocumentDesignsController#update → ThemeDbExportService.export!
       → CREATE TABLE document_designs (+ image_opacity, logo_* cols)
       → INSERT row (values tuple)
       → baked storage/themes/<name>.db
  → (Sub-project B: book_write CoverThemeStyles reads dd[:image_opacity], dd[:logo_*])
```

## Edge Cases

- **Interior doc-types:** neither section renders (gated on `COVER_PANEL_TYPES`); their forms unchanged.
- **Non-front_page cover panels:** get image_opacity, no logo section.
- **Unset values:** `image_opacity` defaults 100; logo columns null → book_write (B) falls back to its current defaults.
- **Export column order:** DDL and INSERT must agree; book_write reads by column name, so order-independent downstream.

## Testing (gem Minitest)

- **Model** (`document_design_test.rb`): `image_opacity` defaults to 100; the new columns persist; `LOGO_POSITIONS` are the valid `logo_position` values; optional `logo_position` inclusion validation (allow_nil).
- **Controller edit** (`document_designs_edit_test.rb`): PATCH a **front_page** document_design with `image_opacity` + logo params → attributes persisted; export re-runs (mirror the existing export-triggered assertion).
- **Export service** (`theme_db_export_service_test.rb`): create a theme with a cover document_design carrying image_opacity + logo values → `export!` → open the baked SQLite → the `document_designs` row has `image_opacity` and `logo_*` columns with the set values (mirror the `cover_type` assertion).
- **Studio render:** the image-opacity section renders for a cover doc-type and is absent for an interior doc-type; the logo section renders only for front_page (a controller edit-view / component assertion).

## Constraints

- **Two repos:** the migration + `db/schema.rb` land in **book_design**; model/controller/component/export/i18n/tests land in the **`design` gem** (remote is SSH `git@github.com:mskim/design.git` — the PAT is read-only; push via SSH at release).
- **book_design migration:** run `bin/rails db:migrate` in book_design (this is book_design's own DB, not book_write's — book_write dev-DB constraints don't apply here).
- **Gem tests need the dummy schema edited (C1):** the migration does NOT feed the gem test suite — `test/dummy/db/schema.rb` must be hand-edited with the 5 columns or all gem tests fail with `no such column`. This is the single riskiest step.
- **i18n:** ko + en only (design engine convention).
- Stage explicit paths; never `git add -A` (the gem has an unrelated `Gemfile.lock` change — do not commit it).

## Success Criteria

1. `Design::DocumentDesign` has `image_opacity` + `logo_width/height/position/offset`; a designer can set them in the studio Layout tab for cover doc-types (logo for front_page).
2. Saving re-bakes the theme SQLite with the new columns (verified by an export-service test reading the baked DB).
3. Interior doc-type forms are unchanged; no book_write changes.
4. Existing themes re-baked so they carry the columns (defaults) for Sub-project B.
5. Gem + book_design tests pass.
