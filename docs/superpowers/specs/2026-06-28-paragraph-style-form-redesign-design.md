# Paragraph-style edit form redesign — Design

**Date:** 2026-06-28
**Status:** Approved (mockup confirmed)
**Component:** `Design::Views::ParagraphStyles::Fields` (the design gem)

## Goal

The paragraph-style edit form is tall and forces scrolling. Redesign it to be
compact and **fit beside the preview at the preview's own height** (~700px on the
EditPage) with no scrolling — while making the field groups easier to scan.

Mockup (approved): `proposed-layout-v2.html` in this session's brainstorm dir.

## The four changes

1. **Fits the preview height** — the whole form is visible at once next to the
   preview; no vertical scroll on the EditPage.
2. **Tight title→field spacing** — minimal gap between a group's title and its
   fields.
3. **Pastel group boxes** — each group is a bordered, lightly-tinted box with its
   title sitting on the **top-left of the box border** (fieldset + legend). **글꼴
   (font) and 텍스트 (text) merge** into one "글꼴 · 텍스트" box.
4. **Inline label + value** — each field is `label | control` on one line (not
   stacked), **two fields per row**.

## Group structure (boxes, in order)

| Box (legend) | Tint | Fields |
| --- | --- | --- |
| 기본 정보 | blue | name, korean_name |
| 글꼴 · 텍스트 | green | font*(full row)*, font_size, scale, **text_color** *(full row)*, text_align, tracking, space_width, text_line_spacing |
| 표 셀 *(only table_heading_cell / table_body_cell)* | slate | vertical_align |
| 굵게 · 강조 | amber | bold_font, bold_text_color, emphasis_font, emphasis_color |
| 간격 | violet | first_line_indent, left_indent, right_indent, space_before, space_after, space_before_in_lines, space_after_in_lines |
| 채우기 | pink | fill_type, fill_gradient_direction, fill_color, fill_ending_color |
| 테두리 | cyan | border_thickness, border_color, **border_side editor**, **corner editor**, corner_radius |
| 안쪽 여백 | orange | padding_top, padding_bottom |

## Layout rules

- **Box:** `fieldset` with a `legend`; pastel `bg` + matching border; legend is a
  small rounded chip on the top-left of the border. Compact padding.
- **Rows:** 2-column grid inside each box; a field is `flex` with a fixed-width
  (~52px), right-aligned label + a flex-1 control (`min-w-0` so long values scroll
  within the control, never overflow — same fix we just applied to the color field).
- **Full-width exceptions** (`span` both columns): the **font select** and any
  **color field** (swatch + CMYK/Hex mode + value are too wide for a half-row).
- **Border editors:** the existing 테두리 면 and 둥근 모서리 widgets sit side-by-side
  inside the 테두리 box, with 모서리 반경 below the corner pad.
- **Density:** ~22px controls, ~11px text — small but legible.

## Constraints / scope

- Works in **both** render contexts that use `Fields`: the full **EditPage**
  (~34rem column) and the **embedded panel** (`properties_panel`, ~28rem). The
  2-col grid collapses gracefully when narrow.
- **Behavior is unchanged** — same field names, inputs, and Stimulus controllers
  (`design--color-mode-field`, `design--border-side-editor`, `design--corner-editor`).
  This is layout/markup + scoped-CSS only.
- The **Save button** stays at the bottom (explicit save, unchanged).
- Out of scope: the EditPage/Panel wrappers, the preview, autosave (already off).

## Implementation outline

- Rewrite `Fields#view_template` + section helpers to emit fieldset boxes and an
  inline `field_row`; merge `font_section`+`text_section`; add per-group tint
  classes.
- Rebuild the scoped `design.css` (new utility classes) and keep the freshness
  test green.

## Testing

- Existing render tests still pass (field `name=`s and inputs unchanged).
- Add assertions for the new structure (fieldset/legend per group, font+text
  merged, inline rows).
- Visual verification: Playwright screenshot of the EditPage form at the real
  preview height — confirm no scroll and groups read clearly.
