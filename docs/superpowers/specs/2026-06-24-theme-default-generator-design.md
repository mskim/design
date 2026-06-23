# Theme Default-Value Generator — Design Spec

**Date:** 2026-06-24
**Status:** Approved (brainstorm) — pending spec review (v2, grounded in real Seoul data)
**Repo:** `design` gem (primary). Hosts (`book_design`, `book_write`) only call the service + wire override-tracking.
**Domain source:** the author's `theme_basic.md` + the live **Seoul** system theme (id 7) as the reference data.

---

## Goal

Compute a theme's layout and heading-font defaults **by rule** from each paper size's dimensions, instead of hand-setting them. Margins/binding scale proportionally; `body_line_count` and heading sizes interpolate between the 신국판 and A4 anchors. Generation fills only values the user hasn't deliberately set; a per-doc_type relevance map means only the paragraph styles a doc_type needs get touched.

## Problem

A designer hand-sets margins, `body_line_count`, and heading sizes per paper size, and base-style generation creates all ~34 named styles regardless of which doc_type uses them. There is (a) no proportional rule for arbitrary new sizes and (b) no doc_type→style relevance used at generation time (the mapping exists as `DOC_TYPE_STYLE_FAMILIES`/`relevant_style_names` but isn't the generation source of truth).

## Reference data (live Seoul theme, id 7)

| size | W×H | L/R | top | bottom | binding | blc | title |
|---|---|---|---|---|---|---|---|
| 사륙판 | 128×188 | 18.5 | 15.0 | 23.4 | 2.5 | 19 | — |
| 국판 | 148×210 | 21.4 | 16.8 | 26.1 | 2.9 | 21 | — |
| **신국판** | 152×225 | **22.0** | **18.0** | **28.0** | **3.0** | **23** | (anchor) |
| 크라운판 | 176×248 | 25.5 | 19.8 | 30.9 | 3.5 | 25 | — |
| 사륙배판 | 188×257 | 27.2 | 20.6 | 32.0 | 3.7 | 26 | — |
| **A4** | 210×297 | **30.4** | **23.8** | **37.0** | **4.1** | 30 | (anchor) |

**Finding:** the current margins are a clean **ratio of dimension** (L/R = W×0.14474, top = H×0.08, bottom = H×0.12444, binding = W×0.01974) — every size fits. So margins are proportional-through-origin, not a two-anchor line with an intercept.

Real base-style names (34, on every theme): `author, blockquote, body, caption, caption_title, cover_author, cover_body, cover_publisher, cover_subtitle, cover_title, footer_left, footer_right, footnote, h2, h3, h4, h5, h6, header_left, header_right, image_caption, ol, quote, seneca_author, seneca_publisher, seneca_title, source, subtitle, table_body_cell, table_heading_cell, title, ul, wing_body, wing_title`. (No `publisher`, `code`, or `index`.)

## Decisions

| # | Decision |
|---|----------|
| 1 | **Scope** = proportional generator + explicit relevance map. Not a doc_type "kind" hierarchy, not a theme-generation rewrite. |
| 2 | **Relevance map** = explicit flat `DOC_TYPE_STYLES = { doc_type => [real style names] }`, materialized from the existing `DOC_TYPE_STYLE_FAMILIES`/`STYLE_FAMILIES` (so it uses real names and already includes poem→h2, chapter→footnote). Designer-curatable. |
| 3 | **Override model** = generate-on-create + edit tracking. Concrete values written; `overridden_fields` per record protects user edits; (re)generation skips them. |
| 4 | **Layer** = the design gem (`GenerationRules` + `DefaultGenerator` + `Overridable` concern); hosts call the service and wire `mark_overridden`. |
| 5 | **Margins/binding** = ratio-of-dimension (matches current data exactly → regeneration of existing sizes is a no-op for margins). |
| 6 | **body_line_count** = two-anchor 신국판 23 → A4 40 (the author's target; **overrides** the current proportional value, e.g. A4 30→40). |
| 7 | **Heading sizes** = scale **down** from the current (flat) base sizes: 신국판 = base×0.75, A4 = base×1.0. Stored as per-`document_design` overrides. Body/list/caption/table/running/`*_body` styles stay fixed. |
| 8 | **Out-of-range sizes extrapolate** linearly (with safety floors). |

## Design

### Components (gem)

```
Design::GenerationRules            # pure functions + constants, NO DB
  ANCHORS = { sin_h: 225, a4_h: 297 }            # height anchors for two-anchor rules
  MARGIN_RATIOS = { left: 22/152.0, right: 22/152.0, top: 18/225.0,
                    bottom: 28/225.0, binding: 3/152.0 }   # from 신국판
  FLOORS = { margin: 5.0, binding: 1.0, body_line_count: 8, heading: 6.0 }
  HEADING_SCALED_STYLES = %w[title subtitle author quote
                             cover_title cover_subtitle cover_author cover_publisher
                             seneca_title seneca_author seneca_publisher wing_title]
  DOC_TYPE_STYLES = { "chapter" => [...real names...], ... }   # see below

  .margins_for(width_mm, height_mm)        -> { left:, top:, right:, bottom:, binding: }
  .body_line_count_for(height_mm)          -> Integer
  .heading_scale_for(height_mm)            -> Float          # 0.75 + 0.25·t_h
  .scaled_size(base_size, height_mm)       -> Float          # base · heading_scale, floored
  .styles_for(doc_type)                    -> [style names]  # DOC_TYPE_STYLES, chapter-set fallback

Design::DefaultGenerator           # DB orchestration; idempotent; skips overridden
  .call(paper_size)                 # fill paper_size layout, then each document_design's headings
  .call_for(document_design)        # heading overrides for one doc_type

Design::Overridable (concern)       # included by PaperSize + ParagraphStyle
  #mark_overridden(*attrs) / #overridden?(attr) / #mark_overridden_from_changes
```

### Interpolation rules

`t_h = (height_mm − 225) / 72` (72 = 297 − 225). No clamp — extrapolate; then apply FLOORS.

| value | formula | 신국판 | A4 |
|---|---|---|---|
| left / right margin | `width_mm · 0.14474` | 22.0 | 30.4 |
| top margin | `height_mm · 0.08` | 18.0 | 23.8 |
| bottom margin | `height_mm · 0.12444` | 28.0 | 37.0 |
| binding | `width_mm · 0.01974` | 3.0 | 4.1 |
| body_line_count | `(23 + 17·t_h).round` | 23 | 40 |
| heading scale `s` | `0.75 + 0.25·t_h` | 0.75 | 1.00 |
| heading size (per scaled style) | `(base_size · s).round(1)`, ≥ 6.0 | base×0.75 | base×1.0 |

- Margins/binding/heading sizes round to **one decimal**; `body_line_count` to integer.
- **Floors** (extrapolation guards): margin ≥ 5.0, binding ≥ 1.0, body_line_count ≥ 8, heading ≥ 6.0. Sub-floor results are clamped to the floor (not errored).
- **Anchor checks:** `margins_for(152,225)` ⇒ {22.0,18.0,22.0,28.0,3.0}; `margins_for(210,297)` ⇒ {30.4,23.8,30.4,37.0,4.1}; `body_line_count_for(225)`⇒23, `(297)`⇒40; `heading_scale_for(225)`⇒0.75, `(297)`⇒1.0; title (base 24): 신국판 18.0, A4 24.0.

> **body_line_count overrides existing data.** Unlike margins (which reproduce current values), the two-anchor blc rule changes existing unoverridden sizes on regeneration (e.g. A4 30→40, 국판 21→19, 사륙판 19→14). This is the author's intent (steeper line-count growth with page size).

### DOC_TYPE_STYLES (relevance map)

Materialized from the live `DOC_TYPE_STYLE_FAMILIES` + `STYLE_FAMILIES` (real names). Families expand to:
`cover`=cover_title/subtitle/author/publisher/body · `seneca`=seneca_title/author/publisher · `wing`=wing_title/body · `heading`=title/subtitle/author/h2/h3/h4/h5/h6 · `body`=body/blockquote/quote/footnote/caption/caption_title/image_caption/ol/ul/source · `running`=header_left/right/footer_left/right · `table`=table_heading_cell/table_body_cell.

| doc_type(s) | families | resulting styles (abbrev.) |
|---|---|---|
| inside_cover, part_cover, document_cover, front_page, back_page | cover | cover_title/subtitle/author/publisher/body |
| seneca | seneca | seneca_title/author/publisher |
| front_wing, back_wing | wing | wing_title/body |
| toc | (explicit) | title, h2, h3, h4 |
| title_page, thanks, dedication | heading+body | title…h6 + body…source |
| blank_page | body | body…source |
| copyright | body+running | body…source + header/footer |
| poem | heading+body+running | …**incl. h2** ✓ |
| chapter, foreword, prologue, appendix, epilogue, help, information | heading+body+running+table | …**incl. footnote** ✓ |

The author's two requested additions (poem→h2, chapter→footnote) are already satisfied by this materialization (h2∈heading, footnote∈body). The table is a **constant the designer may further curate** (e.g. trim h2–h6 from title_page) — that's data tuning, not a code change. Any `doc_type` absent from the map falls back to the **chapter set** *except* the cover-panel types, which are explicitly mapped above (never chapter-fallback).

### What the generator writes

- **Paper-size layout** (4 margins, binding, `body_line_count`) → `paper_size` columns, each only if not in `overridden_fields`.
- **Heading sizes** → for each `document_design`, for each style in `DOC_TYPE_STYLES[doc_type]` that is in `HEADING_SCALED_STYLES`, create a **document-level override** (`DocumentDesign#override_for(name)` — verified: copies the theme base style incl. `font_size`) and set `font_size = scaled_size(base.font_size, height)`, unless that override's `font_size` is in its `overridden_fields`. Non-scaled relevant styles get **no** generated value (they inherit the fixed theme base).

> The base size scaled is the **theme's seeded base style `font_size`** (e.g. live Seoul `title` = 24), *not* the gem's `DEFAULT_HEADING_STYLES` constant (which is only the create-on-demand fallback for styles that don't yet exist). Note `quote` is in `HEADING_SCALED_STYLES` but belongs to the `body` family — so it receives a scaled override for body-bearing doc_types (chapter, title_page, …), which is intended.

### Override tracking

Add `overridden_fields` to `design_paper_sizes` and `design_paragraph_styles`: `t.json "overridden_fields", null: false, default: []`, plus model `attribute :overridden_fields, default: []` (belt-and-suspenders for SQLite, where the JSON column stores text). A `Design::Overridable` concern provides `mark_overridden(*attrs)`, `overridden?(attr)`, and `mark_overridden_from_changes` (marks generatable attrs present in `saved_changes`).
- **Generator** writes a field only if `!overridden?(field)`; never adds to the set.
- **First generation** runs in `after_create` before any user edit → correctly unguarded (set is empty).
- **User edits**: each update path that can change a generatable attr calls `mark_overridden_from_changes`. Concrete paths to wire:
  - gem engine: `Design::PaperSizesController#update`, the paragraph-style update/override actions.
  - book_design: `PaperSizesController#update`, paragraph-style update/override actions.
  - book_write: same paragraph/paper-size update paths (if it exposes them).

### Triggers / idempotency

- `Design::PaperSize after_create` → `DefaultGenerator.call(self)`: fills layout, then loops `document_designs` (typically **empty at creation** in the host generator, since paper sizes precede their documents — so the heading-override loop is a **no-op at paper-size-create time**; that's expected).
- `Design::DocumentDesign after_create` → `DefaultGenerator.call_for(self)`: generates that doc_type's heading overrides (this is where heading work actually happens).
- Explicit **"Regenerate defaults"** host action → `DefaultGenerator.call(paper_size)`, honoring `overridden_fields`.
- All writes idempotent (`find_or_initialize`/`override_for` + skip-overridden), mirroring `ThemeStyleSeeder`. `override_for` is idempotent.

## Data model changes

- Migration (additive): `add_column :design_paper_sizes, :overridden_fields, :json, null: false, default: []` and same on `:design_paragraph_styles`. SQLite stores JSON as text; model-level `attribute … default: []` guarantees an array in memory.
- No column made nullable; no existing default removed.

## Testing

- **`GenerationRules` unit tests** (pure): exact anchors per the "Anchor checks" line; a midpoint (국판 148×210 → margins 21.4/16.8/21.4/26.1/2.9, blc 19); an out-of-range small size (사륙판 128×188 → margins 18.5/15.0/18.5/23.4/2.5, blc 14, title 14.9, **author floored to 6.0**).
- **`DOC_TYPE_STYLES` validity test**: every name in every list (and every `HEADING_SCALED_STYLES` name) exists among a freshly-seeded theme's base-style names. Guards against drift.
- **`DefaultGenerator` tests**: (a) new paper size gets computed margins/blc; (b) a doc_type gets overrides **only** for its `DOC_TYPE_STYLES ∩ HEADING_SCALED_STYLES` (e.g. inside_cover → cover_* overrides, no body/h2); (c) skip-overridden: a field in `overridden_fields` is untouched on regenerate while siblings recompute; (d) idempotency: second call is a no-op / no duplicates.
- **`Overridable` concern test** + **per-host integration test** that the `update` path records the edited attr so a later regenerate preserves it.
- Minitest only; fixtures where practical.

## Risks

- **blc data impact** — regeneration rewrites existing unoverridden `body_line_count`. Accepted (author's intent); documented; protected by `overridden_fields` once a user edits.
- **Heading floor on small styles** — `author` (base 7) floors to 6.0 at all sizes ≤ A4. Accepted per the chosen scale-down model; the floor prevents sub-6pt type.
- **Style-name drift** — a `DOC_TYPE_STYLES`/`HEADING_SCALED_STYLES` name that isn't seeded → `override_for` raises. Mitigated by the validity test (all names verified against real base styles in this spec).
- **Missed host wiring** — an update path that forgets `mark_overridden_from_changes` lets a later regenerate clobber an edit. Mitigated by enumerating the paths + per-host integration tests; the gem engine controllers wire it.

## Out of scope

- doc_type "kind" class hierarchy; rewriting book_design's base-style generation; the host "Regenerate" button UI (gem exposes the service); scaling body/running/table styles; a nullable-column/compute-on-read model.
