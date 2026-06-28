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
  form. Default **unchecked** (= scoped to current doc_type, all sizes). The label
  names what *checking* does:
  - KO label **"모든 문서 유형에 적용"**, helper *"기본값: 이 문서 유형에만 (모든 판형)"*
  - EN label **"Apply to all document types"**, helper *"Default: only this
    document type (all paper sizes)"*
- Confirm copy (checked + shadows): KO *"N개 문서 유형의 개별 설정이 초기화됩니다.
  계속할까요?"* / EN *"This resets per-document-type customizations in N document
  type(s). Continue?"*
- The shadow count is computed at panel render and stamped on a `data-` attribute;
  a `design--save-scope` Stimulus controller intercepts submit and fires
  `confirm()` only when the box is checked and the count > 0.

## Write semantics

On save, `panel_update` computes the new attrs (existing `paragraph_style_params`)
and reads a non-model param `apply_scope` (`"all"` | `"doc_type"`, default
`"doc_type"`), then dispatches:

- **`doc_type` (unchecked, default):** for every paper size in the theme that has a
  `DocumentDesign` of the **current doc_type**, upsert a document-level override of
  this style name with the new attrs. Theme base untouched. Paper sizes lacking
  that doc_type are skipped (not auto-created). Idempotent (upsert).
- **`all` (checked):** write the new attrs to the theme base style, and destroy
  every same-name per-doc_type override across the theme.

Either branch then calls `ThemeDbExportService#export!` **once** and re-renders the
current document's preview (unchanged from today).

Clicking a theme-base style and saving unchecked must **not** mutate the base — the
write is redirected to overrides.

## Code shape

New `Theme` methods (unit-testable, no controller coupling):

- `apply_paragraph_style_to_doc_type!(doc_type, name, attrs)` — the fan-out.
- `apply_paragraph_style_to_all!(name, attrs)` — base write + shadow clear.
- `shadow_override_doc_types(name)` — doc_types that would be reset (for count /
  warning).

`panel_update` (`Design::DocumentDesignEditing`) branches on `params[:apply_scope]`
and calls the matching method, then exports + re-renders preview.

View: checkbox + helper text in `Panel`; `design--save-scope` Stimulus controller
for the conditional confirm.

## Testing (TDD)

- **Model:** fan-out hits all same-doc_type sizes and no others; base-write clears
  shadows; `shadow_override_doc_types` counts correctly; idempotent re-saves.
- **Controller:** `apply_scope=doc_type` creates sibling overrides + leaves base;
  `apply_scope=all` updates base + removes overrides; exactly one export per save.
- **View:** checkbox renders unchecked by default with the shadow-count data
  attribute, only in the document context.

## Out of scope

- No new schema/migration.
- No change to the `.db` export format or downstream consumers.
- The theme-area base editor and table-style editors are unaffected.
