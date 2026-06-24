# Paper-Sizes Area Port — Design Spec (Sub-project #2)

**Date:** 2026-06-24
**Status:** Reviewed & approved — ready for planning (1 correction folded in: `update` must call `mark_overridden_from_changes`; destroy-guard question resolved — no guard, matches book_design)
**Repo:** `design` gem (only). **No book_design change** — book_design registers no paper-size host actions and keeps its own pages until #6.
**Program context:** Sub-project **#2** of "converge the design studio onto book_design's UI." #0 (shell + host-action registry) and #1 (Themes area port) are shipped. This adds full **paper-size create/edit/delete/regenerate** to the gem studio so a theme's paper sizes can be managed in-place from the theme show page, matching book_design. Later: #3 document-designs, #4 paragraph-styles/style-browser, #5 table-styles, #6 retire book_design `Pages::*`.

---

## Goal

Give the gem studio full paper-size management: **create** a new size on a theme, **edit** an existing size's page dimensions / margins / body settings, **delete** a size, and **regenerate** a size's rule-based defaults — all reached from the theme show page's size tabs, all gem-native (book_design inherits nothing here; book_write gets it automatically). Achieve **field parity** with book_design's paper-size editor while keeping the existing base-text-styles list as the entry to base-style editing (sub-project #4).

## Problem

The gem's paper-size support is **edit-only and partial**:

- `Design::Views::PaperSizes::Edit` renders only **margins + binding + body_line_count + toc_page_count** and the base-styles list. It does **not** expose the page-identity fields (`size_name`, `local_name`, `width_mm`, `height_mm`) at all — you can't change a size's name or dimensions from the studio.
- `Design::PaperSizesController` has only `edit` + `update`; the engine routes are `only: [:edit, :update]`. There is **no** `new`/`create` (can't add a size), **no** `destroy` (can't remove one), and **no** way to re-run the default generator on an existing size.
- The model already supports everything (validations, `Overridable` overrides, `after_create DefaultGenerator`, unit conversions, `display_name`) — the gap is purely view + controller + routes.

book_design exposes the full create/edit/delete/regenerate flow over the same model; this ports that surface into the gem.

## Key findings (from exploration)

- **Model is complete — no migration.** `Design::PaperSize` (`app/models/design/paper_size.rb`): `belongs_to :theme`; `has_many :document_designs, dependent: :destroy`; `include Design::Overridable` with `GENERATABLE_FIELDS = left/top/right/bottom/binding margins + body_line_count`; `before_create { capture_explicit_overrides(GENERATABLE_FIELDS) }`; **`after_create { Design::DefaultGenerator.call(self) }`** (a new size auto-derives margins/line-count + its document designs, matching book_design); validations `size_name` presence + uniqueness scoped to `theme_id`, `width_mm`/`height_mm` numericality `> 0`, `body_line_count` integer `> 0`; `MM2PT` unit conversions; `display_name` (`"<local_name> (<w>x<h>mm)"` or `size_name`).
- **Current controller** (`app/controllers/design/paper_sizes_controller.rb`): `before_action :set_theme, :set_paper_size, :ensure_theme_editable`. `update` permits `left/top/right/bottom/binding margins + body_line_count + toc_page_count`, then **`Design::ThemeDbExportService.new(@theme).export!`** and redirects to `theme_path`. `set_paper_size` uses `@theme.paper_sizes.find(params[:id])` (scoped — safe).
- **Current Edit component** (`app/components/design/views/paper_sizes/edit.rb`): renders inside `shell(...)`, breadcrumb (theme → size), `h1 display_name`, the margins/binding/line-count/toc form (POST + hidden `_method=patch` + `authenticity_token`), and `base_styles_section` — `RubyUI::Card` rows per base paragraph style linking to `edit_theme_paper_size_base_paragraph_style_path` (sub-project #4's entry; must not regress).
- **DefaultGenerator** (`app/services/design/default_generator.rb`): `self.call(paper_size)` → `new(paper_size).call`; `fill_layout` computes margins via `GenerationRules.margins_for(w, h)` + `body_line_count_for(h)`, **skips any attr where `@paper_size.overridden?(attr)`**, and `update_columns` the rest. So calling it on an existing size **re-derives defaults for non-overridden fields and preserves manual edits**.
- **Routes** (`config/routes.rb`): `resources :paper_sizes, only: [:edit, :update]` nested under `:themes`, itself nesting `base_paragraph_styles`. Themes already gained `new/create/edit` in #1.
- **Host boundary:** book_design registers **no** paper-size host actions (verified in the brainstorm) — paper sizes are managed entirely through the gem's own routes. #2 is therefore **gem-only**; no `config/initializers/design.rb` change.
- **i18n:** `design.paper_sizes` already has `margins, left/top/right/bottom_margin, binding_margin, body_line_count, toc_page_count, base_text_styles, paper_size_styles`; `design.shared` has `left/top/right/bottom/save/cancel/edit`. **Missing** the page-identity, create, delete, and regenerate keys (listed below).

## Decisions

| # | Decision |
|---|----------|
| 1 | **Gem-only.** All changes live in the `design` gem; book_design and book_write inherit automatically. No host registration change (book_design registers no paper-size actions). |
| 2 | **One `Form` component for new + edit** (URL/method switch on `persisted?`), replacing the current `Edit`. Sections: **Page Size** (`size_name`, `local_name`, `width_mm`, `height_mm`) · **Margins** (left/top/right/bottom + `binding_margin_mm`) · **Body Settings** (`body_line_count`, `toc_page_count`). Plain-div validation errors (the gem has no `RubyUI::Alert`). |
| 3 | **The base-text-styles list stays on the edit case only** (a persisted size has base styles; a brand-new size does not). It is the entry to base-style editing (#4) and must not regress. The new-size form shows no base styles. |
| 4 | **Entry points on the theme show page:** a **＋ New size** affordance near the size tabs → blank create form; an **Edit** affordance on the active size tab → edit form. **Delete** and **Regenerate defaults** are buttons **inside** the edit form (destructive/secondary). The existing "Generate Sizes from [default]" button (a different feature — clones the default size's *styles*) is untouched. |
| 5 | **Full CRUD + regenerate** in the controller: add `new`, `create`, `destroy`, `regenerate`; widen `update`'s permitted params to include the four page-identity fields. Each of create/update/destroy/regenerate re-runs **`Design::ThemeDbExportService.new(@theme).export!`** (mirroring today's `update`) so the baked theme DB stays in sync. All guarded by the existing `ensure_theme_editable`. |
| 6 | **Create relies on the model's `after_create DefaultGenerator`** — a new size auto-derives its margins/line-count (for fields the user left blank) and document designs, exactly as book_design does. The form lets the user pre-set any field; `capture_explicit_overrides` (run `before_create`) marks user-supplied generatable fields as overridden so the generator won't clobber them. |
| 7 | **`update` must mark post-creation edits as overridden** — after a successful `update`, call `@paper_size.mark_overridden_from_changes(Design::PaperSize::GENERATABLE_FIELDS)` (exactly as book_design's `update` does). The gem's current `update` does **not** do this; `capture_explicit_overrides` only runs `before_create`, so without this call a field edited *after* creation would be silently re-derived by the next `regenerate`. The method already exists on `Design::Overridable`. |
| 8 | **`regenerate` = `Design::DefaultGenerator.call(@paper_size)`**, redirect back to edit with a notice. Semantics: it **re-derives defaults for non-overridden fields and preserves fields the user explicitly overrode** (per `Overridable` + Decision 7). It is *not* a "reset to factory defaults that discards my overrides" — clearing overrides is out of scope (see Risks). |
| 9 | **No per-size `show` route.** book_design's `create` redirects to a per-size `show` page; the gem deliberately has none (theme-show tabs browse a size's docs). The gem's `create`/`regenerate` redirect to `edit_theme_paper_size_path`, `destroy`/cancel to `theme_path`. Intentional divergence from book_design. |

## Design

### Components (gem)

- **`Design::Views::PaperSizes::Form` (new)** — one Phlex `Design::Views::Base` component for both new and edit, rendered inside `shell(...)`. Constructor `initialize(theme:, paper_size:, base_styles: [])`. Behaviour:
  - **Action/method switch on `@paper_size.persisted?`:** new → POST `theme_paper_sizes_path(@theme)`; edit → POST `theme_paper_size_path(@theme, @paper_size)` with hidden `_method=patch`. Both emit the `authenticity_token` hidden input (matching the current Edit).
  - **Breadcrumb + heading:** theme → (`display_name` when persisted / `t("…new_title")` when new).
  - **Section "Page Size":** text `size_name` (required), text `local_name`, number `width_mm`, number `height_mm` (step `0.1`). Reuses the existing `number_field`/`field_value` helpers (lifted from `Edit`) for mm decimals.
  - **Section "Margins":** the four margin fields + `binding_margin_mm` (step `0.1`) — same as today.
  - **Section "Body Settings":** integer `body_line_count`, integer `toc_page_count`.
  - **Submit + actions:** primary submit (`t("…create_button")` when new / `t("…update_button")` when persisted) + Cancel link to `theme_path(@theme)` (reuse `design.shared.cancel`). On the **edit** case, also render a **Regenerate defaults** button (POST `regenerate_theme_paper_size_path`) and a **Delete** button (DELETE `theme_paper_size_path`, with `t("…delete_confirm")` confirmation) — both as secondary/destructive affordances.
  - **Validation errors:** when `@paper_size.errors.any?`, render a plain `div` (no `RubyUI::Alert` — it does not exist in the gem) listing `@paper_size.errors.full_messages`.
  - **Base text styles:** on the **edit** case only (`@paper_size.persisted? && @base_styles.any?`), keep the existing `base_styles_section` (`RubyUI::Card` rows → `edit_theme_paper_size_base_paragraph_style_path`). Unchanged from `Edit`.
- **`Design::Views::PaperSizes::Edit` (current)** — folded into / replaced by `Form`. (Its `number_field`/`field_value`/`base_styles_section`/`base_style_row` helpers move into `Form`.)
- **`Design::Views::Themes::Show` (small edit)** — add the two entry-point affordances to the size selector: a **＋ New size** link → `new_theme_paper_size_path(@theme)`, and an **Edit** link on the active size tab → `edit_theme_paper_size_path(@theme, active_size)`. No other show change.

### Controller + routes (gem)

`Design::PaperSizesController`:

- **`new`** — `@paper_size = @theme.paper_sizes.new`; render `Form` (no base styles).
- **`create`** — `@paper_size = @theme.paper_sizes.new(paper_size_params)`; on save → `ThemeDbExportService.new(@theme).export!`, redirect to `edit_theme_paper_size_path` (or `theme_path`) with `created_notice`; on invalid → re-render `Form` `status: :unprocessable_entity`. (`after_create DefaultGenerator` runs automatically inside the save.)
- **`edit`** — unchanged behaviour, now renders `Form` (with `base_styles`).
- **`update`** — `paper_size_params` **widens** to add `size_name, local_name, width_mm, height_mm` (the full list then matches book_design's permit exactly). On success, **call `@paper_size.mark_overridden_from_changes(Design::PaperSize::GENERATABLE_FIELDS)`** (new — mirrors book_design `update`) before `export!`, so edited generatable fields are protected from a later `regenerate`. Invalid → re-render `Form` 422 (today it re-renders `Edit`).
- **`destroy`** — `@paper_size.destroy`; `ThemeDbExportService.new(@theme).export!`; redirect to `theme_path` with `deleted_notice`. (`dependent: :destroy` cascades the size's document designs **and** paragraph styles — both declared on the model.) **No default/last-size guard** — book_design's `destroy` is a plain `@paper_size.destroy` with no guard, so plain destroy is the correct parity behaviour (see Risks).
- **`regenerate`** (member POST) — `Design::DefaultGenerator.call(@paper_size)`; `ThemeDbExportService.new(@theme).export!`; redirect to `edit_theme_paper_size_path` with `regenerated_notice`.
- `set_paper_size` stays `@theme.paper_sizes.find(params[:id])` and is skipped for `new`/`create` (no `:id`). `ensure_theme_editable` continues to guard every action.

Engine `config/routes.rb`: `resources :paper_sizes` gains `:new, :create, :destroy` and `post :regenerate, on: :member` (from `only: [:edit, :update]` → `only: [:new, :create, :edit, :update, :destroy]` + the member route). `base_paragraph_styles` nesting unchanged.

### Model — no change

`Design::PaperSize` already has the validations, `Overridable` overrides, `after_create DefaultGenerator` (auto-generate on create), unit conversions, and `display_name`. **No migration, no model edit.**

### i18n (gem, ko.yml + en.yml only)

Add under `design.paper_sizes`: `page_size, size_name, local_name, width, height, body_settings, new_title, create_button, update_button, delete, delete_confirm, regenerate, regenerated_notice, created_notice, deleted_notice`. Reuse existing `margins, binding_margin, body_line_count, toc_page_count, base_text_styles` and `design.shared.{left,top,right,bottom,save,cancel,edit}`. ko.yml + en.yml only; `fallbacks=[:en]` covers the other locales. Keysets must match across both files.

## Testing

Minitest only; mirror existing gem component/controller test patterns. Paper-size flows **do not shell out** (no `PreviewService`), so nothing heavy to stub — but `create`/`update`/`destroy`/`regenerate` call `ThemeDbExportService#export!`, which writes a per-theme SQLite file; tests run against the dummy app's `tmp/themes` and exercise it for real (or stub `ThemeDbExportService` if the suite prefers not to touch disk — match how the existing themes controller tests handle export).

- **Component (`Form`):** renders all three sections' fields for both the new case (`paper_sizes.new`, no base styles, create button, action = collection path) and the edit case (persisted, base-styles list present, update button + Regenerate + Delete, action = member path + `_method=patch`); renders a validation-error div when `@paper_size.errors` is populated.
- **Controller/integration:**
  - `new` renders the form.
  - `create` with valid params adds a size, redirects, and (via `after_create`) the new size has `document_designs` generated; `export!` invoked.
  - `create` with invalid params (blank `size_name` / non-positive `width_mm`) → 422 + errors, no size created.
  - `update` round-trips the new page-identity fields (`size_name`/`local_name`/`width_mm`/`height_mm`) **and** the existing margin/line-count fields; invalid → 422.
  - `update` of a generatable field (e.g. `body_line_count`) marks it overridden — **edit via `update`, then `regenerate`, assert the edited value survives** (proves the `mark_overridden_from_changes` call). A non-overridden field is recomputed by the same regenerate.
  - `destroy` removes the size (and cascades its document designs); `export!` invoked.
  - `regenerate` re-derives defaults for non-overridden fields **and preserves an overridden field**; `export!` invoked.
  - Every action still enforces `ensure_theme_editable` (a non-editable theme → 403 / redirect, matching the existing guard's behaviour).

## Risks

- **Regenerate semantics may surprise.** `DefaultGenerator` preserves overridden fields, so "Regenerate defaults" on a size whose fields were all manually set is largely a no-op. This matches the `Overridable` contract and book_design, but the button label/help text should make clear it **re-derives** defaults rather than **resets** to them. A true "reset (clear overrides)" is **out of scope**.
- **Destroy of the default / last size — RESOLVED (no guard).** book_design's `destroy` (`app/controllers/paper_sizes_controller.rb:55-59`) is a plain `@paper_size.destroy` with **no** guard against deleting the default/only size. The gem's plain `destroy` therefore matches book_design exactly; **no guard is added** (adding one would diverge from parity). If a "can't delete the last size" rule is ever wanted, it's a follow-up for both repos.
- **ThemeDbExportService on every write.** create/update/destroy/regenerate each re-export the theme DB (as `update` already does) — acceptable and consistent with today; no async needed at this scale.
- **Form field parity drift.** book_design may expose additional paper-size fields; the spec targets the gem model's actual columns (`size_name, local_name, width_mm, height_mm` + margins/binding + body_line_count/toc_page_count). If book_design shows a field the gem model lacks, it's out of scope (would need a migration — defer).
- **book_write** — gets create/edit/delete/regenerate automatically via the gem routes; registers no actions; additive, no migration.

## Out of scope (later sub-projects)

Base paragraph-style editing reached from the edit form's styles list (#4), document-design editing (#3), table styles (#5), retiring book_design's own paper-size pages (#6), a "reset to factory defaults (clear overrides)" action, and any async/batched theme-DB export.
