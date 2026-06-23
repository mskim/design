# Theme Default-Value Generator — Design Spec

**Date:** 2026-06-24
**Status:** Approved (brainstorm) — pending spec review
**Repo:** `design` gem (primary). Hosts (`book_design`, `book_write`) only call the service.
**Domain source:** the author's `theme_basic.md` (taxonomy of doc_types / paragraph styles / sizing rules).

---

## Goal

Let a theme's layout and heading-font defaults be **computed by rule** from a paper size's dimensions instead of hand-set, by interpolating between two reference sizes (신국판 and A4). Generation fills only values the user hasn't deliberately set, and a per-doc_type relevance map ensures only the paragraph styles a doc_type actually needs are generated.

## Problem

Today a book designer hand-sets margins, `body_line_count`, and heading font sizes for every paper size, and the base-style generator (`book_design`'s `ThemeGeneratorService`) creates all ~43 named paragraph styles regardless of which doc_type uses them. Two gaps:

1. **No proportional rule.** Margins / `body_line_count` / heading sizes don't scale with paper dimensions; each size is configured manually. Reference values exist only as fixed presets (`DEFAULT_SIZES`: 신국판, A4, 사륙판, …).
2. **No doc_type → style relevance used at generation time.** The mapping exists (`DOC_TYPE_STYLE_FAMILIES`, `relevant_style_names`) but isn't the source of truth for *what gets generated* — so irrelevant styles are created/considered.

## Key findings (from exploration)

- **Models.** `Design::PaperSize` (width_mm, height_mm, four `*_margin_mm` + `binding_margin_mm` [NOT NULL, static defaults], `body_line_count` [NOT NULL, default 23], `toc_page_count`). `Design::DocumentDesign` (`doc_type` from `ALL_DOC_TYPES`, layout fields; `body_line_count` is **nullable** and falls back to paper_size). `Design::ParagraphStyle` is **polymorphic** (`styleable` = Theme for base styles, or DocumentDesign for per-document overrides); most style columns are nullable; `font_size` is nullable.
- **Existing relevance mapping.** `DocumentDesign::DOC_TYPE_STYLE_FAMILIES` + `STYLE_FAMILIES` + `relevant_style_names(doc_type)` already express which styles a doc_type uses, as *families*. `DEFAULT_HEADING_STYLES` already encodes 신국판 heading sizes (title 18 / subtitle 14 / author 11 / publisher 10).
- **Override pattern already in the codebase.** `DocumentDesign#override_for(base_name)` creates a document-level override of a theme base style; `merged_paragraph_styles` merges base + overrides; several `effective_*` methods provide computed fallbacks. The "store an override on the document" mechanism we need already exists.
- **Reference data.** 신국판 = 152×225, margins L22 T18 R22 B28, binding 3, body_line_count 23. A4 = 210×297, margins L25 T20 R25 B30, binding 3, body_line_count 40 (target). Currently in `book_design`'s `DEFAULT_SIZES`.
- **Existing generation seam.** `Design::Theme after_create :seed_default_styles` → `Design::ThemeStyleSeeder` (idempotent, `find_or_create_by!`) seeds table + cell styles only. Our generator mirrors this idempotent style.

## Decisions

| # | Decision |
|---|----------|
| 1 | **Scope = proportional generator + explicit relevance map.** Not a doc_type "kind" class hierarchy, not a full theme-generation rewrite. |
| 2 | **Relevance map = flat `DOC_TYPE_STYLES = { doc_type => [ordered style names] }`.** The generator iterates only this list per doc_type. Replaces family-indirection as the source of truth for *generation*. |
| 3 | **Override model = generate-on-create + edit tracking.** Computed values are written as concrete column values; an `overridden_fields` set per record records user-edited fields; (re)generation skips them. |
| 4 | **Layer = the design gem.** `Design::GenerationRules` (pure functions + constants) and `Design::DefaultGenerator` (DB orchestration) live in the gem; hosts call `Design::DefaultGenerator.call(paper_size)`. |
| 5 | **Out-of-range sizes extrapolate** linearly from the two anchors (with safety floors), rather than clamping. A smaller-than-신국판 book gets proportionally smaller values. |
| 6 | **Scaled heading sizes are stored as per-`document_design` overrides**, not theme base styles — because heading size depends on paper *height* and a theme may hold multiple paper sizes. Body / list / caption / table / header-footer styles stay fixed on the theme base. |

## Design

### Components (gem)

```
Design::GenerationRules          # pure: no DB, no Rails models
  REFERENCE = {
    sin: { w: 152, h: 225, left: 22, top: 18, right: 22, bottom: 28, binding: 3,
           body_line_count: 23 },
    a4:  { w: 210, h: 297, left: 25, top: 20, right: 25, bottom: 30, binding: 3,
           body_line_count: 40 }
  }
  HEADING_BASE = { "title" => 18, "subtitle" => 14, "quote" => 12,
                   "author" => 11, "publisher" => 10 }   # 신국판 sizes
  HEADING_SCALED_STYLES = HEADING_BASE.keys   # only these scale with height
  DOC_TYPE_STYLES = { "chapter" => [...], "inside_cover" => [...], ... }

  .margins_for(width_mm, height_mm) -> { left:, top:, right:, bottom:, binding: }
  .body_line_count_for(height_mm)   -> Integer
  .heading_sizes_for(height_mm)     -> { "title" => Float, ... }   # scaled HEADING_BASE
  .styles_for(doc_type)             -> [style names]               # DOC_TYPE_STYLES lookup

Design::DefaultGenerator           # orchestrates DB writes; idempotent; skips overridden
  .call(paper_size)                 # fill paper_size layout + per-doc_type heading overrides
```

### Interpolation rules

Two linear parameters (no clamp — extrapolate):
```
t_w = (width_mm  - 152) / 58      # 58 = 210 - 152
t_h = (height_mm - 225) / 72      # 72 = 297 - 225
```

| value | formula | 신국판 | A4 |
|---|---|---|---|
| left / right margin | `22 + 3·t_w` | 22 | 25 |
| top margin | `18 + 2·t_h` | 18 | 20 |
| bottom margin | `28 + 2·t_h` | 28 | 30 |
| binding margin | fixed `3` | 3 | 3 |
| body_line_count | `(23 + 17·t_h).round` | 23 | 40 |
| heading scale factor `f` | `1 + 0.333·t_h` (= 24/18 at A4) | 1.0 | 1.333 |
| heading size (per style) | `HEADING_BASE[name] · f` | 18/14/12/11/10 | 24/18.7/16/14.7/13.3 |

- Margins and heading sizes round to **one decimal**; `body_line_count` to **integer**.
- **Safety floors** (extrapolation guard): `body_line_count` ≥ 8; each margin ≥ 5.0 mm; heading size ≥ 6.0 pt. (Values, confirmable in review; intent = never produce a degenerate layout for a tiny page.)
- **Fixed styles** (body, h2–h6, ol, ul, code, blockquote, caption, table_heading_cell, table_body_cell, header_left/right, footer_left/right) are **never scaled** — they inherit the theme's `base_body_font_size`. Only `HEADING_SCALED_STYLES` get computed sizes.

> Note: this taxonomy follows `theme_basic.md` (HeadingPara = title/subtitle/quote/author/publisher are page-height-proportional; h2–h6 are fixed BodyPara), which differs from the code's current `STYLE_FAMILIES["heading"]` that lumps h2–h6 in. `DOC_TYPE_STYLES` + `HEADING_SCALED_STYLES` become the new source of truth; the legacy family constants are not used by the generator (left in place for `relevant_style_names`/UI until separately retired).

### DOC_TYPE_STYLES (relevance map)

Flat, ordered, derived from `DOC_TYPE_STYLE_FAMILIES` + `theme_basic.md`. Authoritative table (final names confirmed in review against the seeded base-style names):

```ruby
DOC_TYPE_STYLES = {
  # frontmatter
  "title_page"     => %w[title subtitle author publisher],
  "copyright"      => %w[body header_left header_right footer_left footer_right],
  "inside_cover"   => %w[title subtitle author publisher],
  "blank_page"     => %w[body],
  "thanks"         => %w[title body],
  "dedication"     => %w[title body],
  "foreword"       => %w[title subtitle body h2 h3 header_left header_right footer_left footer_right],
  "prologue"       => %w[title subtitle body h2 h3 header_left header_right footer_left footer_right],
  "information"    => %w[title body h2 h3 header_left header_right footer_left footer_right],
  "toc"            => %w[title h2 h3],
  # bodymatter
  "part_cover"     => %w[title subtitle],
  "document_cover" => %w[title subtitle],
  "chapter"        => %w[title subtitle body h2 h3 h4 h5 h6 quote ol ul code blockquote caption
                          table_heading_cell table_body_cell
                          header_left header_right footer_left footer_right],
  "poem"           => %w[title author body header_left header_right footer_left footer_right],
  # rearmatter
  "appendix"       => %w[title subtitle body h2 h3 header_left header_right footer_left footer_right],
  "epilogue"       => %w[title subtitle body h2 h3 header_left header_right footer_left footer_right],
  "index"          => %w[title body h2 h3],
  # any unmapped doc_type falls back to the chapter set
}.freeze
```

The generator's job per doc_type: for each name in `DOC_TYPE_STYLES[doc_type]` that is in `HEADING_SCALED_STYLES`, ensure a **document-level override** exists with the computed `font_size` (unless that field is overridden by the user). Non-heading names are *relevant* (they should exist as theme base styles) but get **no** computed size from this generator — they're left to the existing base-style seeding.

### Where generated values are written

- **Paper-size layout** (margins, binding, `body_line_count`): written to the `paper_size` columns directly.
- **Heading sizes**: written as `document_design` paragraph-style **overrides** (`DocumentDesign#override_for(name)`), one per scaled heading style relevant to that doc_type, with the height-scaled `font_size`.

### Override tracking

Add `overridden_fields` (JSON, default `[]`) to `design_paper_sizes` and `design_paragraph_styles`.

- A small concern `Design::Overridable` provides `mark_overridden(*attrs)`, `overridden?(attr)`, and a scope helper.
- **Generator** writes a field only if `!overridden?(field)`; it never adds to the set.
- **User edits** (host update path) call `mark_overridden(:changed_attr)` for each generatable attr the user changed. (Host wires this in its `update` actions for paper sizes and paragraph styles; the gem provides the concern + a convenience that marks from `saved_changes`.)
- `regenerate` re-runs `DefaultGenerator.call`, which by construction skips overridden fields → **user edits always win**.

### Triggers

- `Design::PaperSize after_create` → `Design::DefaultGenerator.call(self)`. Fills layout, then iterates the paper size's `document_designs` and generates each doc_type's heading overrides. (Idempotent: safe if document_designs are created later — generation also runs/upserts when a `document_design` is created.)
- `Design::DocumentDesign after_create` → generate that doc_type's heading overrides for its paper size (so adding a doc_type later is covered).
- **Explicit "Regenerate defaults"** host action → `DefaultGenerator.call(paper_size)`; honors `overridden_fields`. (Host UI button; out of gem scope beyond exposing the service.)
- All writes idempotent (`find_or_initialize` + skip-overridden), mirroring `ThemeStyleSeeder`.

## Data model changes

- Migration: add `overridden_fields` JSON (default `[]`, null: false) to `design_paper_sizes` and `design_paragraph_styles`. Additive only.
- No column becomes nullable; no existing default removed (we chose concrete generate-on-create, not nullable-fallback).

## Testing

- **`GenerationRules` unit tests** (pure, no DB): exact anchor values — `margins_for(152,225)` ⇒ {22,18,22,28,3}; `margins_for(210,297)` ⇒ {25,20,25,30,3}; `body_line_count_for(225)`⇒23, `(297)`⇒40; `heading_sizes_for(225)["title"]`⇒18, `(297)["title"]`⇒24. A **midpoint** (e.g. 국판 148×210) asserts the interpolated values. An **out-of-range** small size (사륙판 128×188) asserts extrapolation + that floors hold.
- **`DefaultGenerator` tests**: (a) creating a paper size fills computed margins/`body_line_count`; (b) only `DOC_TYPE_STYLES[doc_type]`’s scaled styles get document overrides — irrelevant styles get none; (c) **skip-overridden**: a field in `overridden_fields` is left untouched on regenerate while siblings recompute; (d) **idempotency**: calling twice creates no duplicates and changes nothing the second time.
- **`Overridable` concern test**: `mark_overridden` records attrs; `overridden?` reflects it; generator respects it.
- Minitest only; fixtures for theme/paper_size where practical.

## Risks

- **Taxonomy drift** between `theme_basic.md` and the code's legacy `STYLE_FAMILIES` (h2–h6 placement, `quote`/`author` as heading). Mitigation: `DOC_TYPE_STYLES` + `HEADING_SCALED_STYLES` are the single source of truth for generation; the table is reviewed against the actual seeded base-style names before implementation.
- **Style-name mismatches** (a name in `DOC_TYPE_STYLES` that no base style seeds) → override points at a non-existent base. Mitigation: a test asserts every `DOC_TYPE_STYLES` name exists in the theme's seeded base styles (or is intentionally heading-only).
- **Override-tracking gaps**: if a host update path forgets to `mark_overridden`, a later regenerate could clobber that edit. Mitigation: provide a `mark_overridden_from_changes` helper and document the one-line host wiring; the gem's own engine controllers wire it.
- **Extrapolation extremes**: floors prevent degenerate layouts; values for absurd sizes are clamped at the floor (logged, not errored).

## Out of scope

- doc_type "kind" class hierarchy (ChapterKind < …) — the flat map covers the need.
- Rewriting `book_design`'s `ThemeGeneratorService` (base-style creation) or moving it into the gem.
- The host "Regenerate" button UI (the gem exposes the service; host wires the button separately).
- Scaling body / running / table styles (intentionally fixed).
- Nullable-column migration / compute-on-read (we chose concrete generate-on-create).
