# One size per book design (sizing)

Part of "themes become book_designs" (2026-10-29). Sibling work, owned by other sessions:
the `.book_design` v5 zip format (designcraft_rb `DesignCraftRb::BookDesign`), Theme <-> file
loader/exporter (`Design::BookDesignFile`, design gem branch feat/book-design-files), the
IDML/.designcraft import, and the studio left rail (`views/sidebar.rb`, branch
feat/studio-tree-like-book-write). **Do not edit `app/components/design/views/sidebar.rb`.**

## Goal

A design (`Design::Theme`) has exactly one `PaperSize`. Another size is another design, made by
"copy for another size" from this one with the existing generation rules. Multi-size generation
goes away. Existing multi-size themes keep working until collapsed by a rake task.

## Decisions

- Invariant enforced on create only: `PaperSize` validates its theme has no other size
  (`on: :create`). Existing multi-size rows are left alone (no validation on update).
- Copy for another size = `Design::SizedCopyService`: `ThemeCloneService` copies the source's
  default size into a new theme, then `SizeGenerationService#rescale!(from:, to:)` rescales the
  copy's one size to the target dimensions with the rules `generate!` used (margins ∝ width/height,
  body_line_count from content height / body leading, body font kept, h2–h6 by line-count ratio,
  headings and spacing by height). Name defaults to `"<source name> <local_name>"` (e.g.
  `클래식 사륙판`, `Classic A5`); the copy keeps the source's locale and owner rules (a system
  source with `Design.authoring?` gives a system copy; otherwise the current user's custom copy).
- Standard sizes for the form live in the gem: `Design::PaperSize::STANDARD_SIZES`
  (size_name, local_name, width_mm, height_mm — 신국판, 사륙판, 국판, 크라운판, 사륙배판, A4, plus
  A5 148×210 named "A5" for English). Custom width/height allowed too.
- Old entry points stay routable so the rail (owned elsewhere) keeps working until it switches:
  `POST themes/:id/generate_sizes` and `GET themes/:id/paper_sizes/new` redirect to
  `new_theme_size_copy_path`; `PaperSizes#create` on a theme with a size is refused the same way;
  `PaperSizes#destroy` of a theme's only size is refused.
- Data: `Design::SingleSize.collapse!(theme, split: false)` keeps the default (first) size and
  removes the rest; with `split: true` each other size first becomes its own design
  (`"<name> <local_name>"`) via `ThemeCloneService(paper_size:)`. Rake `design:single_size`
  (dry run unless `APPLY=1`; `SPLIT=1` to split) over starter themes; book designs (book_id set)
  are already single-size and skipped. Re-exports each changed theme's `.db`.
- Legacy SQLite `.book_design` import (`Design::ThemeImportService`) keeps only the file's first
  paper size.
- Rollout: run `design:single_size APPLY=1` on a book_write install only after book_write's
  size-follows-design change (book_write branch feat/single-size-designs) is deployed, and prefer
  `SPLIT=1` there so each old size stays available as its own design.

## Tasks

1. `PaperSize` create validation + `STANDARD_SIZES`; `SizeGenerationService#rescale!(from:, to:)`
   extracted from `generate!`'s loop body (`generate!` kept for now, calling it); `SizedCopyService`.
   Tests: validation; rescale gives the same values `generate!` gave for a size; copy is one size,
   named, rescaled, own `.db` exported, source untouched.
2. `Design::SizeCopiesController` (`resource :size_copy, only: [:new, :create]` under themes) with
   a Phlex form (standard size select + custom width/height + name), ko/en locales; redirects for
   generate_sizes / paper_sizes#new / #create; refuse destroying the only size. Controller tests.
3. `Design::SingleSize` + `design:single_size` rake task; `ThemeImportService` first size only.
   Tests.
4. (book_design app) `ThemeGeneratorService` creates one size (param, default 신국판) instead of
   `DEFAULT_SIZES.each`; tests.
