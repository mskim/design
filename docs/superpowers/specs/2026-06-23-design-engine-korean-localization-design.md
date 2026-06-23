# Design Engine Korean Localization — Design Spec

**Date:** 2026-06-23
**Status:** Approved (brainstorm) — pending spec review
**Repos touched:** `design` gem (primary), `book_design` (host locale default)

---

## Goal

Render the entire design-engine authoring UI in Korean, by extending the gem's existing i18n: replace the remaining hardcoded English strings in the design view components with `t("design.…")` calls, add Korean (`ko.yml`) + English (`en.yml`) translations, and default book_design's app locale to `:ko`.

## Problem

The design engine's editor UI is mostly hardcoded English (PropertiesPanel, paragraph-style Fields/Panel/Form, the standalone Edit shell, the paper-size editor, the preview error). Only the **themes** UI and **doc-type names** are already Korean. The user (a Korean book designer) wants the whole authoring UI in Korean.

## Key findings (from exploration)

1. **The gem already has a working i18n foundation.** `config/locales/{ko,en}.yml` exist (themes UI + `design.doc_types.*` already translated). The engine loads them (`config.i18n.load_path += Dir[root.join("config","locales","*.yml")]`). `Design::ApplicationController` has `around_action :switch_design_locale` that applies the host's locale via `Design.config.locale_for`, falling back to `I18n.default_locale`.
2. **book_design wires the host locale:** `config/initializers/design.rb` sets `c.locale_for = -> { I18n.locale }`. But book_design has **no `default_locale`** set (so it's `:en`) and only a `config/locales/en.yml`. So even after translating, book_design must default to `:ko` for Korean to show.
3. **Scope (the remaining hardcoded components, ~110 strings):** `document_designs/properties_panel.rb` (~53 — incl. `Has Document Cover` + the four Header/Footer slot labels), `paragraph_styles/fields.rb` (~40 incl. section headings), `document_designs/edit.rb` (~9 — incl. the `theme page` link text), `document_designs/preview.rb` (~8 — overlay labels `Title/Subtitle/Author/Publisher`, fallbacks `Heading/Body`, `TOC Entry`, and `Generating preview...`), `paper_sizes/edit.rb` (~9 — incl. `Margins (mm)` + `Base Text Styles`), `paragraph_styles/{panel,form}.rb` (~7), `document_designs/preview_error.rb` (~1). (book_design renders some of these inside its own shell, but they're gem components.) **Left literal by design:** `(base)` badge, `IDX` template placeholder, ` › ` breadcrumb separator, `CMYK`/`Hex`/`RGB`, `pt`/`mm`, font/style-name values, and `(%{korean_name})` interpolations.

## Decisions

| # | Decision |
|---|---|
| 1 | **Extend, don't rebuild.** Add `t("design.…")` calls to the remaining components; add keys to the existing `ko.yml`/`en.yml` under the `design.*` namespace, mirroring `design.themes.*`. |
| 2 | **Translations** are drafted by the assistant and corrected by the user in `design/docs/i18n-ko-glossary.md` — that file is the **canonical source** for the Korean strings. `en.yml` carries the original English (the fallback). |
| 3 | **book_design defaults to `:ko`:** set `config.i18n.default_locale = :ko` + `available_locales = [:ko, :en]`, and add a `config/locales/ko.yml` for any book_design-host strings later (out of scope now). The gem already follows the host locale, so book_write stays English. |
| 4 | **Select values stay English; only labels are translated** (the one non-mechanical part — see Design). |

## Design

### i18n key structure

Namespaced by component under `design.*`, mirroring the existing `design.themes.*`:
- `design.properties_panel.*` — tab names, section headings, field labels, helper text.
- `design.fields.*` — paragraph-style field labels + section headings (Identity/Font/Text/…).
- `design.panel.*` — Back, New Style, Save, Cancel, Revert to base, error heading.
- `design.editor.*` — standalone Edit shell + Preview (Preview, Loading…, Base/Document Styles, Edit →, shared-styles note).
- `design.paper_sizes.*` — Binding Margin, TOC Page Count, Top/Bottom/Left/Right, Body Line Count.
- `design.preview.*` — "Preview generation failed".
- `design.options.<attr>.*` — select option labels (see below).

The exact Korean text comes from `design/docs/i18n-ko-glossary.md` (user-edited). The plan transcribes that file into `ko.yml`/`en.yml`; the glossary stays as the human-readable record.

### The value-vs-label rule (the only non-mechanical part)

Many selects render the stored DB value as its own visible label, e.g. `select_field("V-Align", :heading_v_align, %w[center top bottom])` → `<option value="center">center</option>`. The value is persisted and read by the renderer, so it **must not change** — only the visible text becomes Korean (가운데/위/아래).

**Mechanism:** the field helpers gain an optional localized-label lookup. `select_field(label, attr, values, i18n_scope: nil)` renders each option as `option(value: v) { i18n_scope ? t("design.options.#{i18n_scope}.#{v}") : v }`. Call sites that need localized option labels pass the scope (e.g. `i18n_scope: "v_align"`); the option `value` is always the raw English token. The same applies to the anchor-position dropdown, fill type, gradient direction, corner radius, text align, and heading-background type. Selects whose values are already opaque (font names, theme styles) are unaffected.

### Components & their changes

For each in-scope component: replace literal display strings with `t("design.<ns>.<key>")`; for selects with human-readable values, route option labels through `design.options.<attr>.<value>`. No layout, CSS, or DB changes. `CMYK`/`Hex`/`RGB` and `pt`/`mm` stay literal. `%{...}` interpolations (e.g. `Current: %{filename}`) are preserved.

### Locale wiring (already mostly done)

No gem controller change needed — `switch_design_locale` already applies `Design.locale_for`. book_design: add `config.i18n.default_locale = :ko` and `config.i18n.available_locales = [:ko, :en]` (in `config/application.rb`), plus a stub `config/locales/ko.yml` so `:ko` is a valid load target. `I18n.fallbacks` keeps `:en` as the fallback, so a missing Korean key shows English (not a crash).

## Testing

- **Key parity test** (in the gem): every key under `design.*` present in `ko.yml` must also exist in `en.yml` and vice-versa — catches "translation missing" and orphans. (A simple recursive-flatten comparison of the two YAMLs.)
- **Render-in-Korean test:** render `PropertiesPanel` and `Fields` with `I18n.with_locale(:ko)`; assert representative Korean strings appear (e.g. `레이아웃`, `자간`) and the corresponding English does NOT.
- **Value-guard test:** assert a localized select still emits `value="center"` (and `value="top"`, etc.) while its visible text is Korean — the DB contract is preserved.
- **No-missing-translation test:** render each in-scope component under `:ko` and assert the output contains no `translation missing` marker.
- **No-English-leftover guard:** render each in-scope component under `:ko` and assert its visible text contains none of the known English labels (a denylist drawn from the glossary's English column, e.g. `Layout`, `Tracking`, `Margins`, `Title`, `Generating preview`). This catches the failure mode the other tests can't — a string that was never converted to a `t()` call at all (which is exactly how the review-found omissions slipped through). Exempt the intentionally-literal tokens (`CMYK`, `Hex`, `pt`, `mm`, `(base)`, font names).
- book_design: a smoke test/assertion that `I18n.default_locale == :ko`.

## Risks

- **Value/label mix-up** (translating a stored token) → covered by the value-guard test; the renderer would otherwise break (e.g. heading_v_align="가운데" is unknown).
- **Missing keys** → parity + no-missing tests; `:en` fallback prevents a hard failure.
- **Interpolation loss** (`%{filename}`) → preserved verbatim from the glossary; spot-checked in tests.
- **Glossary ↔ yml drift** → the plan generates yml from the glossary in one pass; the glossary is the record, the yml is generated. (Not auto-synced afterward — future string additions update both.)
- **book_write** pins the gem; this change is additive (new keys + `t()` calls that fall back to English when locale is `:en`), so book_write keeps rendering English with no change required.

## Out of scope

- Translating book_design's **own** host UI (`Pages::*` chrome, toolbar) beyond what's needed — the request is the design *engine* UI. (A book_design `ko.yml` stub is added but host-string translation is a separate effort.)
- A runtime language switcher / per-user locale (book_design simply defaults to `:ko`).
- Locales other than Korean/English.
- Any non-UI change (rendering, models, routes).
