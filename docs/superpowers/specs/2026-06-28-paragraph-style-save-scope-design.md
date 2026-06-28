# Paragraph-Style Save Scope — Design

**Date:** 2026-06-28
**Status:** Approved (ready for implementation plan)
**Component:** `design` gem (studio editor)

## Problem

Editing a paragraph style from the document-design edit panel currently writes
to the theme **base** style, so the change lands on **every document type in
every paper size**. Authors want a narrower default: a change should apply only
to the **current document type, across all paper sizes** — not to other document
types. The broad "all document types" behaviour should remain available behind an
explicit opt-in.

## Background: the style cascade

The effective cascade for a document is **theme base → document override**
(`DocumentDesign#merged_paragraph_styles`). The persistence levels that exist:

- **theme base** — `Theme#base_paragraph_styles`, one row per style name; the root
  for every doc_type in every paper size.
- **document override** — a `ParagraphStyle` on one `DocumentDesign`. A
  `DocumentDesign` is the intersection of one **paper size × one doc_type**.

There is **no** level meaning "this doc_type, all sizes." That set is realised as
a *group* of document_designs — one per paper size, all sharing the doc_type.

## Decisions

1. **Mechanism: fan-out overrides (no migration).** The default scope is realised
   by writing document-level overrides onto every same-doc_type `DocumentDesign`
   across paper sizes, reusing the existing override mechanism. Chosen over a new
   schema level because document overrides are a record type the `.db` export
   (`ThemeDbExportService`) and the downstream PDF engine (`doc_processor_rb` via
   `bookcheego`) already understand — no cross-repo format change.

2. **Checked = "all document types" overwrites everything.** Write the new value
   to the theme base **and** delete same-name per-doc_type overrides across the
   theme, so the value is uniform everywhere (honours "all" literally).

3. **Warn only when shadows exist.** A checked save that would discard one or more
   same-name per-doc_type overrides shows a `confirm()` naming the count. No
   shadows → silent save.

4. **Surface: document-design edit context only.** The checkbox appears next to
   Save in the panel reached via `panel_update` (where a doc_type exists). The
   theme-area base editor does not get it.

## UX

- Checkbox next to **저장 / Save** in `Design::Views::ParagraphStyles::Panel`'s
  form. Default **unchecked** (= scoped to current doc_type, all sizes).
- **The Panel is the document-context editor for theme-, paper-, AND
  document-level styles.** `panel` / `panel_update` render this same `Panel` for
  `level: "theme" | "paper" | "document"` (`find_panel_style`,
  document_design_editing.rb:110-116) — all within a `@document_design` context.
  The checkbox therefore renders in *every* Panel invocation (a `@document_design`
  always exists at `panel_update`). The theme-area editors
  (`BaseParagraphStylesController`, `ThemeParagraphStylesController`) render a
  *different* component (`Design::Views::ParagraphStyles::Form`), so they are
  already immune — no guard needed there.
- The label names what *checking* does:
  - KO label **"모든 문서 유형에 적용"**, helper *"기본값: 이 문서 유형에만 (모든 판형)"*
  - EN label **"Apply to all document types"**, helper *"Default: only this
    document type (all paper sizes)"*
- Confirm copy (checked + shadows): KO *"N개 문서 유형의 개별 설정이 초기화됩니다.
  계속할까요?"* / EN *"This resets per-document-type customizations in N document
  type(s). Continue?"*
- **Plumbing the shadow count to the view.** `Panel` does not currently receive a
  `document_design`. Add constructor params `document_design:` and
  `save_scope_shadow_count:` to `Panel`; thread `@document_design` from both
  `render_paragraph_style_panel` (document_design_editing.rb) and `EditPage`
  (which already holds `@document_design` and constructs the Panel). The count is
  `theme.shadow_override_doc_types(style.name).size`, stamped on a `data-` attribute.
- The form carries `data-controller="design--panel-autosave design--save-scope"`
  with `data-action="submit->design--save-scope#confirmScope
  submit->design--panel-autosave#save"`. `save-scope` runs **first**; when the box
  is checked and the count > 0, it shows `confirm()` and, on cancel, calls
  `event.preventDefault()` + `event.stopImmediatePropagation()` so the autosave
  handler never runs. No checkbox / no shadows → it does nothing and the submit
  proceeds normally.

## Write semantics

On save, `panel_update` reads the new attrs (existing `paragraph_style_params`) and
a non-model param `apply_scope` (`"all"` | `"doc_type"`, default `"doc_type"`).
`apply_scope` is a sibling top-level param, untouched by
`params.require(:paragraph_style).permit(...)`, read via `params[:apply_scope]`.
It then dispatches:

- **`doc_type` (unchecked, default):** enumerate
  `@theme.document_designs.where(doc_type: @document_design.doc_type)` —
  `Theme#document_designs` is `through: :paper_sizes`, so this is every same-doc_type
  design across all paper sizes, **including the current `@document_design`**. For
  each, `upsert_paragraph_style!(name, attrs)`. The theme base is left untouched.
  The current document is always in this set, so its override (and therefore the
  re-rendered preview) always reflects the edit. Idempotent (upsert respects the
  `(styleable_type, styleable_id, name)` uniqueness).
  - **Which attrs:** the raw `paragraph_style_params` (blank fields included as
    nil). Because all paper sizes share **one** theme base for a given name
    (`merged_paragraph_styles` resolves against `paper_size.theme.base_paragraph_styles`),
    writing the identical override attrs to each same-doc_type design makes every
    sibling resolve **identically** — no per-size divergence.
- **`all` (checked):** **upsert** the theme base style — find-or-create a
  `ParagraphStyle` with `styleable: @theme` and this name, then update it with the
  attrs (a style may exist only as a document override with **no** base row, e.g.
  freshly-created or default heading styles, so this must create the base row when
  absent, not raise). Then destroy every same-name per-doc_type override across the
  theme (`@theme.document_designs` → each `paragraph_styles.where(name:)`),
  **including the current document's**, so the base value shows everywhere.

Either branch then calls `ThemeDbExportService#export!` **once** and re-renders the
current document's preview (unchanged from today).

Clicking a theme- or paper-level style and saving unchecked must **not** mutate
that base record — the write is redirected to document overrides via the
enumeration above.

## Code shape

New `Theme` methods (unit-testable, no controller coupling):

- `apply_paragraph_style_to_doc_type!(doc_type, name, attrs)` — fan-out: upsert an
  override on each `document_designs.where(doc_type:)`.
- `apply_paragraph_style_to_all!(name, attrs)` — upsert the base
  `ParagraphStyle` (styleable: self), then destroy same-name overrides across the
  theme. (`Theme` has no `upsert_paragraph_style!` today — add a private
  find-or-create-base helper or inline it.)
- `shadow_override_doc_types(name)` — the **distinct** doc_types (not a row count)
  that currently have a same-name override; `.size` is the warning count. A doc_type
  with overrides in several sizes counts once.

`panel_update` (`Design::DocumentDesignEditing`) branches on `params[:apply_scope]`
and calls the matching method, then exports + re-renders preview.

View: checkbox + helper text in `Panel` (gated on the new `document_design:` param);
`design--save-scope` Stimulus controller for the conditional confirm.

## Testing (TDD)

- **Model:** fan-out hits all same-doc_type sizes (including the current document)
  and no other doc_types; fan-out leaves the theme base untouched; `apply_..._to_all!`
  creates the base row when none exists *and* updates it when it does, and clears
  same-name overrides across the theme (current document included);
  `shadow_override_doc_types` returns distinct doc_types (a doc_type with overrides
  in multiple sizes counts once); idempotent re-saves (no duplicate rows).
- **Controller:** `apply_scope=doc_type` creates sibling overrides + leaves base;
  `apply_scope=all` upserts base + removes overrides; saving a theme-level style
  unchecked does not mutate the base; exactly one export per save.
- **View:** checkbox renders unchecked by default with the shadow-count data
  attribute when `document_design:` is supplied; the autosave + save-scope
  controllers/actions are both present on the form.

## Out of scope

- No new schema/migration.
- No change to the `.db` export format or downstream consumers.
- The theme-area base editor and table-style editors are unaffected.
