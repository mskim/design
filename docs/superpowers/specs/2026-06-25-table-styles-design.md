# Table Styles Editor — Design Spec (Sub-project #5)

**Date:** 2026-06-25
**Status:** Approved (brainstorm) — pending spec review
**Repo:** `design` gem only. book_design + book_write inherit. The editor is built so book_design can **retire its own** `TableStylesController` + `Pages::TableStyles::*` in #6, registering its preview renderer through the new hook.
**Program context:** Sub-project **#5** of "converge the design studio onto book_design's UI." #0 (shell + host-action registry), #1 (themes), #2 (paper-sizes), #3 (doc-designs toolbar), #4 (style browser + form parity) shipped. This ports book_design's **table-style editor** into the gem; the lone host-only piece (the preview renderer) is surfaced through a config hook. Later: #6 retire book_design `Pages::*`.

**Guiding principle (from the user, reaffirmed across #4):** *one source of truth — match book_design, don't diverge.* Host-only renders are exposed through a seam (here a config hook), not dropped.

---

## Goal

Add a full table-style editor to the gem studio: a per-theme grid of table-style cards on the theme show page, each opening a two-pane editor (preview left, form right) that edits the `Design::TableStyle` border / background / cell-text fields, with **Reset to defaults** — a structural port of book_design's `TableStylesController` + `Pages::TableStyles::*`. The host-only preview render is surfaced through a new `Design.config.table_style_preview` hook (book_design registers its renderer; until a host does, the preview area shows a placeholder).

## Problem

The gem **has the `Design::TableStyle` model** (`app/models/design/table_style.rb`: `ALLOWED_NAMES = grid/zebra/striped/minimal/simple`; columns `border_width/border_color/border_style`, `header_background/alternate_row_background/header_text_color/body_text_color`, `cell_padding/outer_border_width/header_separator_width`, `header_font_weight`; `BORDER_STYLES = %w[full horizontal none outer_only]`, `FONT_WEIGHTS = %w[normal bold]`; `belongs_to :theme`; uniqueness on `name` scoped to `theme_id`) and seeds 5 presets on theme creation via `Design::ThemeStyleSeeder` — but has **zero editing UI** (no controller, routes, or views). Table styles can't be edited from the gem studio.

book_design has the full editor; it's pure-UI-portable **except** the preview, which is rendered by host-only `TableStylePreviewRenderer` → `TableStyleResolver` + `SingleTablePdf` + Vips (none in the gem).

## Key findings (from exploration)

- **book_design controller** (`table_styles_controller.rb`): `show` (redirect to edit), `edit`, `update`, `reset`; `set_theme`/`set_table_style`; 11 permitted params (border_width, border_color, border_style, header_background, alternate_row_background, header_text_color, body_text_color, cell_padding, outer_border_width, header_separator_width, header_font_weight). **`reset` calls `ThemeStyleSeeder.reset(@theme, @table_style.name)`** — and the **gem's `Design::ThemeStyleSeeder` already has `self.reset(theme, name)`** (`theme_style_seeder.rb:59`, kept in sync with book_design). So `reset` ports with no new model/service code.
- **book_design preview** (`table_style_previews_controller.rb` → `TableStylePreviewRenderer.call(theme, table_style)` returns a JPG blob, served via `send_data … type: "image/jpeg"`). The renderer uses `TableStyleResolver`/`SingleTablePdf`/`TableStylePreviewSample`/Vips — **host-only**.
- **book_design Edit** (`pages/table_styles/edit.rb`): full-screen `h-screen flex` two-pane — left preview (`turbo_frame_tag "preview_frame"` + `<img src=preview_theme_table_style_path(theme, ts, t: …)>`), right `w-96` form panel (header back-link + "<Name> Table Style", the Form, a Reset button with `turbo_confirm`).
- **book_design Form** (`pages/table_styles/form.rb`): POST + `_method=patch` to `theme_table_style_path`; sections **Borders** (width, style `BORDER_STYLES`, color, outer width, header separator), **Backgrounds** (header bg, alt-row bg), **Cell Text** (header color, body color, header weight `FONT_WEIGHTS`, cell padding); `field`/`color_field`/`select_field`/`row`/`section` inline helpers; Save + Done(`theme_path`). Color fields use `data-controller="color-field"` with `picker`/`text` targets + `pickerChanged`/`textChanged` actions — **identical API to the gem's `design--color-field`** (`color_field_controller.js`), so a 1:1 swap.
- **book_design theme-show grid** (`pages/themes/show.rb` `render_table_styles`): a `grid-cols-2…lg:grid-cols-5` of `<a href=edit_theme_table_style_path>` cards, each an `aspect-[4/3]` `<img src=preview_theme_table_style_path>` + capitalized name + "Borders, colors, padding".
- **Gem config** (`lib/design.rb`): `Design::Configuration` exposes settable hooks via `attr_accessor` (`current_user, authorize, …, themes_dir`). Adding `:table_style_preview` is the seam; `Design.config.table_style_preview` is a callable the host sets. (Same shape as the other config callables.)
- **Dead tokens:** book_design's components use `text-muted-foreground`, `bg-background`, `border-input`, `bg-neutral-100`, `focus:ring-ring` — translate each to explicit slate utilities (program rule: no token authoring).

## Decisions

| # | Decision |
|---|----------|
| 1 | **Preview seam = a `Design.config.table_style_preview` config hook** (callable `->(theme, table_style) { jpg_blob }`). `Design::TableStylePreviewsController#show` calls it and `send_data`s the blob. book_design registers its `TableStylePreviewRenderer` through this hook **in #6** (gem-only now). An image preview is data, not an action descriptor, so a config callable (not the #0 action registry) is the right seam. |
| 2 | **Placeholder when no host renderer is registered.** The Edit preview pane and the theme-show cards check `Design.config.table_style_preview.present?` — render the `<img>` only then; otherwise a styled "no preview" box. No broken images. The preview controller returns `head :not_found` if the hook is unset (defensive; the components won't request it then). |
| 3 | **Port the controller verbatim:** `Design::TableStylesController` show/edit/update/reset, 11-field `table_style_params`, `reset` → `Design::ThemeStyleSeeder.reset(@theme, @table_style.name)`. Guarded by the studio's existing designer authorization + an editable-theme check consistent with the other gem editors (`ensure_theme_editable`-style). |
| 4 | **Routes:** `resources :table_styles, only: [:show, :edit, :update] do member { get :preview, to: "table_style_previews#show", as: :preview; post :reset } end` nested under `resources :themes`. |
| 5 | **`Design::Views::TableStyles::Edit` + `Form`**, ports of book_design's, **wrapped in the gem `shell(...)`** (studio chrome — the convergence target; book_design's chrome-less full-screen version is pre-shell and adopts the shell in #6) with the two-pane (preview left / form right) as the shell body. Explicit slate/blue utilities. Color fields wired to `design--color-field`. |
| 6 | **Theme-show grid:** add a "Table Styles" section to `Design::Views::Themes::Show` mirroring book_design's `render_table_styles` (cards link to `edit_theme_table_style_path`; preview-or-placeholder per Decision 2). |
| 7 | **Explicit save** (Save + Done + Reset buttons), matching book_design — NOT panel-autosave. |
| 8 | **Gem-only.** No book_design change in #5 (book_design registers the preview hook + retires its pages in #6). No migration (model already complete). |

## Design

### Config seam (gem)
- `Design::Configuration`: add `:table_style_preview` to the `attr_accessor` list.
- `Design::TableStylePreviewsController#show`: find theme + `theme.table_styles.find(params[:id])`; `blob = Design.config.table_style_preview&.call(theme, table_style)`; if blob → `expires_now; send_data blob, type: "image/jpeg", disposition: "inline"`; else `head :not_found`. Rescue `ActiveRecord::RecordNotFound` → 404.

### Controller + routes (gem)
- `Design::TableStylesController` — as Decision 3. Renders `Design::Views::TableStyles::Edit`.
- Routes — as Decision 4.

### Components (gem)
- **`Design::Views::TableStyles::Edit`** — `shell(title: "<Name> Table Style", …)` wrapping a two-pane `div(flex)`: left preview pane (`turbo_frame_tag "preview_frame"` → `<img src=preview_theme_table_style_path(theme, ts, t: cache_buster)>` when `Design.config.table_style_preview.present?`, else placeholder box), right form panel rendering `Design::Views::TableStyles::Form` + the Reset form (POST `reset_theme_table_style_path`, `turbo_confirm`).
- **`Design::Views::TableStyles::Form`** — POST + `_method=patch` to `theme_table_style_path`; the three sections via local `field`/`color_field`/`select_field`/`row`/`section` helpers (ported; color_field wired to `design--color-field` targets/actions); Save + Done(`theme_path`); plain-div errors.
- **`Design::Views::Themes::Show`** — add `table_styles_section` (Decision 6).

### i18n (gem, ko + en)
`design.table_styles.*`: section nav header ("Table Styles"), `edit_suffix` ("Table Style"), section headers (Borders/Backgrounds/Cell Text), field labels (width, style, color, outer_width, header_sep, header_bg, alt_row_bg, header_color, body_color, header_weight, cell_padding), `reset`, `reset_confirm`, `save`, `done`, `no_preview`, card subtitle. Identical keysets (parity test).

## Testing (Minitest)

- **Controller:** `edit` renders the editor (sections + reset button); `update` round-trips the 11 fields (persist + redirect); invalid → 422; `reset` re-seeds the named preset's defaults (set a field, reset, assert it returns to the seeded default); `show` redirects to edit. All under an editable theme (auth guard enforced — a non-editable/system theme → 403).
- **Preview endpoint:** with `Design.config.table_style_preview` stubbed to return a blob → `send_data` 200 image/jpeg; with it unset → `head :not_found`. (Reset the hook in `ensure`.)
- **Components:** Edit renders the preview `<img>` when the hook is registered and the placeholder when not; Form renders the three sections with the right field names; theme-show renders the table-styles grid linking to each edit path.
- **Locale parity:** `test/i18n/locale_parity_test.rb` green.

## Risks

- **Preview is placeholder until a host registers the hook.** In #5, no host registers `table_style_preview`, so the gem editor + theme-show grid show the "no preview" box everywhere. The editor is fully functional for *editing*; the preview lights up when book_design (or book_write) registers a renderer (book_design in #6). Documented; matches #4's deferred PDF-link pattern.
- **`reset` semantics:** `ThemeStyleSeeder.reset(theme, name)` re-seeds the named preset's defaults (overwriting current values). The Reset button's `turbo_confirm` makes this explicit. Confirm the gem's `reset` overwrites (not merges) — it mirrors book_design's.
- **`shell` wrapping vs book_design's chrome-less editor (Decision 5):** a deliberate convergence choice (studio consistency); book_design adopts it in #6. If it looks cramped in the shell, the two-pane can drop to a max-width container — but match the other gem editors first.
- **Color-field API drift:** the gem's `design--color-field` is confirmed identical to book_design's `color-field` (picker/text targets, pickerChanged/textChanged). Wire to `design--color-field`; do not reintroduce a `color-field` controller.
- **Cosmetic only:** no migration, no model change, no book_design change; book_write/book_design get the editor automatically on the next gem bump (preview placeholder until a host registers the hook).

## Out of scope (later)

book_design's preview renderer internals (`SingleTablePdf`/`TableStyleResolver`/Vips — stay host-only, surfaced via the hook), book_design registering the hook + retiring its `TableStylesController`/`Pages::TableStyles::*` (#6), any in-gem table PDF rendering, and per-document-design table-style overrides (the model is theme-level only).
