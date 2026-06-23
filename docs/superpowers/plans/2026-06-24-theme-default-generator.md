# Theme Default-Value Generator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Compute a theme's layout (margins, binding, body_line_count) and heading font sizes by rule from each paper size's dimensions, filling only un-overridden values, using a per-doc_type relevance map.

**Architecture:** A pure `Design::GenerationRules` module (constants + math, no DB), a `Design::DefaultGenerator` service (DB orchestration, idempotent, skips overridden fields), and a `Design::Overridable` concern (tracks which fields the user set). `after_create` hooks on `PaperSize`/`DocumentDesign` trigger generation; hosts wire override-tracking into their update paths.

**Tech Stack:** Rails 8.1 engine, Minitest, SQLite. Spec: `design/docs/superpowers/specs/2026-06-24-theme-default-generator-design.md`.

**Repos:** `DG = /Users/mskim/Development/ruby/gems/design` (gem — Tasks 1–4). `BD = /Users/mskim/Development/book/book_design` (host — Task 5).

**Conventions (verified):**
- Gem tests build the DB by `load`ing `test/dummy/db/schema.rb` (no migrations) — add columns there for gem tests.
- The gem does **NOT** seed the 34 named base paragraph styles (only `ThemeStyleSeeder` → table + cell styles). So gem tests that need `title`/`subtitle`/etc. base styles must **create them in the test**.
- `Design::DocumentDesign#override_for(name)` (`app/models/design/document_design.rb`) returns an existing doc-level override or creates one copying the theme base style (incl. `font_size`); it does `base_paragraph_styles.find_by!(name:)` (raises if the base is missing).
- `width_mm`/`height_mm` are BigDecimal — convert with `.to_f` before math.
- Minitest only. `bin/rails test test/path/x_test.rb` from each repo root. Commit to `main`. **Never run `db:*` in BD except additive `db:migrate`** (BD holds real data).

---

## File Structure

**`DG` (gem):**
- Create `app/services/design/generation_rules.rb` — `Design::GenerationRules` (pure: family arrays, `DOC_TYPE_STYLES`, `HEADING_SCALED_STYLES`, `MARGIN_RATIOS`, `FLOORS`, `margins_for`, `body_line_count_for`, `heading_scale_for`, `scaled_size`, `styles_for`).
- Create `app/services/design/default_generator.rb` — `Design::DefaultGenerator`.
- Create `app/models/concerns/design/overridable.rb` — `Design::Overridable`.
- Modify `app/models/design/paper_size.rb` — include concern, `GENERATABLE_FIELDS`, `before_create` capture, `after_create` generate.
- Modify `app/models/design/paragraph_style.rb` — include concern, `attribute` default.
- Modify `app/models/design/document_design.rb` — `after_create` heading generation.
- Modify `test/dummy/db/schema.rb` — add `overridden_fields` to two tables, bump version.
- Tests: `test/services/design/generation_rules_test.rb`, `test/services/design/default_generator_test.rb`, `test/models/design/overridable_test.rb`.

**`BD` (host) — Task 5:**
- Create `db/migrate/<ts>_add_overridden_fields_to_design.rb`.
- Modify `app/controllers/paper_sizes_controller.rb` + the paragraph-style controller(s) — call `mark_overridden_from_changes` after user updates; add a `regenerate` action.

---

## Task 1 — `Design::GenerationRules` (pure rules)

**Files:** Create `DG/app/services/design/generation_rules.rb`, `DG/test/services/design/generation_rules_test.rb`.

- [ ] **Step 1: Write the failing test**

`DG/test/services/design/generation_rules_test.rb`:
```ruby
require "test_helper"

class Design::GenerationRulesTest < ActiveSupport::TestCase
  R = Design::GenerationRules

  test "margins reproduce both anchors" do
    assert_equal({ left: 22.0, top: 18.0, right: 22.0, bottom: 28.0, binding: 3.0 }, R.margins_for(152, 225))
    assert_equal({ left: 30.4, top: 23.8, right: 30.4, bottom: 37.0, binding: 4.1 }, R.margins_for(210, 297))
  end

  test "midpoint (국판 148x210) margins" do
    assert_equal({ left: 21.4, top: 16.8, right: 21.4, bottom: 26.1, binding: 2.9 }, R.margins_for(148, 210))
  end

  test "body_line_count two-anchor 23..40" do
    assert_equal 23, R.body_line_count_for(225)
    assert_equal 40, R.body_line_count_for(297)
    assert_equal 19, R.body_line_count_for(210)   # 국판
  end

  test "heading scale + scaled_size hit anchors, floor applies" do
    assert_in_delta 0.75, R.heading_scale_for(225), 0.0001
    assert_in_delta 1.0,  R.heading_scale_for(297), 0.0001
    assert_equal 18.0, R.scaled_size(24, 225)      # title 신국판
    assert_equal 24.0, R.scaled_size(24, 297)      # title A4
    assert_equal 6.0,  R.scaled_size(7, 225)       # author 7×0.75=5.25 -> floor 6.0
  end

  test "out-of-range small size extrapolates with floors (사륙판 128x188)" do
    assert_equal({ left: 18.5, top: 15.0, right: 18.5, bottom: 23.4, binding: 2.5 }, R.margins_for(128, 188))
    assert_equal 14, R.body_line_count_for(188)
  end

  test "styles_for is real names; every relevance/scaled name is a known base style" do
    known = R::FAMILY_NAMES   # union of all family arrays (the real base-style vocabulary)
    R::DOC_TYPE_STYLES.each_value { |list| assert_empty(list - known, "unknown names: #{(list - known).inspect}") }
    assert_empty(R::HEADING_SCALED_STYLES - known)
    assert_includes R.styles_for("poem"), "h2"          # author-requested
    assert_includes R.styles_for("chapter"), "footnote" # author-requested
    assert_equal R.styles_for("chapter"), R.styles_for("nonexistent_type")  # chapter fallback
  end
end
```

- [ ] **Step 2: Run it; verify it FAILS** — `cd /Users/mskim/Development/ruby/gems/design && bin/rails test test/services/design/generation_rules_test.rb` (uninitialized constant).

- [ ] **Step 3: Implement `Design::GenerationRules`**

`DG/app/services/design/generation_rules.rb`:
```ruby
module Design
  module GenerationRules
    module_function

    SIN_H  = 225.0
    H_SPAN = 297.0 - 225.0   # 72.0

    MARGIN_RATIOS = {
      left:    22.0 / 152.0, right: 22.0 / 152.0,
      top:     18.0 / 225.0, bottom: 28.0 / 225.0,
      binding: 3.0  / 152.0
    }.freeze

    FLOORS = { margin: 5.0, binding: 1.0, body_line_count: 8, heading: 6.0 }.freeze

    # --- real base-style families (mirror DocumentDesign::STYLE_FAMILIES, real names) ---
    COVER   = %w[cover_title cover_subtitle cover_author cover_publisher cover_body].freeze
    SENECA  = %w[seneca_title seneca_author seneca_publisher].freeze
    WING    = %w[wing_title wing_body].freeze
    HEADING = %w[title subtitle author h2 h3 h4 h5 h6].freeze
    BODY    = %w[body blockquote quote footnote caption caption_title image_caption ol ul source].freeze
    RUNNING = %w[header_left header_right footer_left footer_right].freeze
    TABLE   = %w[table_heading_cell table_body_cell].freeze
    FAMILY_NAMES = (COVER + SENECA + WING + HEADING + BODY + RUNNING + TABLE).uniq.freeze

    # Display styles whose font_size scales with page height.
    HEADING_SCALED_STYLES = %w[
      title subtitle author quote
      cover_title cover_subtitle cover_author cover_publisher
      seneca_title seneca_author seneca_publisher wing_title
    ].freeze

    DOC_TYPE_STYLES = {
      "title_page"     => HEADING + BODY,
      "blank_page"     => BODY,
      "copyright"      => BODY + RUNNING,
      "inside_cover"   => COVER,
      "part_cover"     => COVER,
      "document_cover" => COVER,
      "thanks"         => HEADING + BODY,
      "dedication"     => HEADING + BODY,
      "foreword"       => HEADING + BODY + RUNNING + TABLE,
      "prologue"       => HEADING + BODY + RUNNING + TABLE,
      "toc"            => %w[title h2 h3 h4],
      "chapter"        => HEADING + BODY + RUNNING + TABLE,
      "poem"           => HEADING + BODY + RUNNING,
      "appendix"       => HEADING + BODY + RUNNING + TABLE,
      "epilogue"       => HEADING + BODY + RUNNING + TABLE,
      "help"           => HEADING + BODY + RUNNING + TABLE,
      "information"    => HEADING + BODY + RUNNING + TABLE,
      "front_page"     => COVER,
      "back_page"      => COVER,
      "seneca"         => SENECA,
      "front_wing"     => WING,
      "back_wing"      => WING
    }.transform_values(&:freeze).freeze

    def t_h(height_mm) = (height_mm.to_f - SIN_H) / H_SPAN

    def margins_for(width_mm, height_mm)
      w = width_mm.to_f; h = height_mm.to_f
      {
        left:    floored((w * MARGIN_RATIOS[:left]).round(1),    :margin),
        top:     floored((h * MARGIN_RATIOS[:top]).round(1),     :margin),
        right:   floored((w * MARGIN_RATIOS[:right]).round(1),   :margin),
        bottom:  floored((h * MARGIN_RATIOS[:bottom]).round(1),  :margin),
        binding: floored((w * MARGIN_RATIOS[:binding]).round(1), :binding)
      }
    end

    def body_line_count_for(height_mm)
      [ (23 + 17 * t_h(height_mm)).round, FLOORS[:body_line_count] ].max
    end

    def heading_scale_for(height_mm) = 0.75 + 0.25 * t_h(height_mm)

    def scaled_size(base_size, height_mm)
      [ (base_size.to_f * heading_scale_for(height_mm)).round(1), FLOORS[:heading] ].max
    end

    def styles_for(doc_type)
      DOC_TYPE_STYLES.fetch(doc_type) { DOC_TYPE_STYLES.fetch("chapter") }
    end

    def floored(value, kind) = [ value, FLOORS[kind] ].max
    private_class_method :floored
  end
end
```

- [ ] **Step 4: Run the test; verify it PASSES.**

- [ ] **Step 5: Commit**
```bash
cd /Users/mskim/Development/ruby/gems/design
git add app/services/design/generation_rules.rb test/services/design/generation_rules_test.rb
git commit -m "feat(theme-gen): GenerationRules — proportional layout + heading rules"
```

---

## Task 2 — `overridden_fields` column + `Design::Overridable` concern

**Files:** Modify `DG/test/dummy/db/schema.rb`; create `DG/app/models/concerns/design/overridable.rb`; modify `DG/app/models/design/paper_size.rb` + `paragraph_style.rb`; create `DG/test/models/design/overridable_test.rb`.

- [ ] **Step 1: Add the column to the dummy schema** (so gem tests have it).

In `DG/test/dummy/db/schema.rb`: bump the version line to `version: 2` and add, inside both `create_table "design_paper_sizes"` and `create_table "design_paragraph_styles"` blocks:
```ruby
    t.json "overridden_fields", default: [], null: false
```

- [ ] **Step 2: Write the failing concern test**

`DG/test/models/design/overridable_test.rb`:
```ruby
require "test_helper"

class Design::OverridableTest < ActiveSupport::TestCase
  setup { @theme = Design::Theme.create!(name: "O #{SecureRandom.hex(3)}", locale: "ko") }

  test "new paper size defaults to empty overridden_fields" do
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    assert_equal [], ps.reload.overridden_fields
  end

  test "explicitly provided generatable attrs are captured as overridden on create" do
    ps = @theme.paper_sizes.create!(size_name: "X", width_mm: 152, height_mm: 225, top_margin_mm: 99)
    assert ps.overridden?(:top_margin_mm)
    refute ps.overridden?(:left_margin_mm)   # left at default -> not captured
  end

  test "mark_overridden persists" do
    ps = @theme.paper_sizes.create!(size_name: "Y", width_mm: 152, height_mm: 225)
    ps.mark_overridden(:left_margin_mm)
    assert ps.reload.overridden?(:left_margin_mm)
  end

  test "mark_overridden_from_changes marks only changed generatable attrs" do
    ps = @theme.paper_sizes.create!(size_name: "Z", width_mm: 152, height_mm: 225)
    ps.update!(left_margin_mm: 12)
    ps.mark_overridden_from_changes(%w[left_margin_mm top_margin_mm])
    assert ps.reload.overridden?(:left_margin_mm)
    refute ps.overridden?(:top_margin_mm)
  end
end
```
> NOTE: this test will also exercise Task 3's `after_create` generator once it exists; for Task 2 the `PaperSize after_create` is not yet added, so margins stay at defaults. The assertions above don't depend on generation. Run after Step 3–5.

- [ ] **Step 3: Run it; verify it FAILS** — `bin/rails test test/models/design/overridable_test.rb` (no `overridden?`).

- [ ] **Step 4: Implement the concern + include it**

`DG/app/models/concerns/design/overridable.rb`:
```ruby
module Design
  module Overridable
    extend ActiveSupport::Concern

    included do
      attribute :overridden_fields, default: []
    end

    def overridden?(attr) = overridden_fields.include?(attr.to_s)

    def mark_overridden(*attrs)
      hit = attrs.map(&:to_s) - overridden_fields
      return if hit.empty?
      self.overridden_fields = overridden_fields + hit
      save!(validate: false) if persisted?
    end

    # Call AFTER a user-driven update: marks generatable attrs that just changed.
    def mark_overridden_from_changes(generatable)
      mark_overridden(*(generatable.map(&:to_s) & saved_changes.keys))
    end

    private

    # Call in before_create: protect generatable attrs the creator set explicitly.
    def capture_explicit_overrides(generatable)
      self.overridden_fields = overridden_fields | (generatable.map(&:to_s) & changed)
    end
  end
end
```

In `DG/app/models/design/paper_size.rb` (add near the top of the class body):
```ruby
    include Design::Overridable
    GENERATABLE_FIELDS = %w[left_margin_mm top_margin_mm right_margin_mm bottom_margin_mm binding_margin_mm body_line_count].freeze
    before_create { capture_explicit_overrides(GENERATABLE_FIELDS) }
```

In `DG/app/models/design/paragraph_style.rb` (add in the class body):
```ruby
    include Design::Overridable
    GENERATABLE_FIELDS = %w[font_size].freeze
```
> `ParagraphStyle` gets NO `before_create` capture — its overrides are created BY the generator; user edits are marked via the update path (Task 5).

- [ ] **Step 5: Run the test; verify it PASSES.**

- [ ] **Step 6: Commit**
```bash
git add test/dummy/db/schema.rb app/models/concerns/design/overridable.rb app/models/design/paper_size.rb app/models/design/paragraph_style.rb test/models/design/overridable_test.rb
git commit -m "feat(theme-gen): overridden_fields column + Overridable concern"
```

---

## Task 3 — `DefaultGenerator#fill_layout` + PaperSize trigger

**Files:** Create `DG/app/services/design/default_generator.rb`; modify `DG/app/models/design/paper_size.rb`; create `DG/test/services/design/default_generator_test.rb`.

- [ ] **Step 1: Write the failing test**

`DG/test/services/design/default_generator_test.rb`:
```ruby
require "test_helper"

class Design::DefaultGeneratorTest < ActiveSupport::TestCase
  setup { @theme = Design::Theme.create!(name: "G #{SecureRandom.hex(3)}", locale: "ko") }

  test "creating a paper size fills computed margins + body_line_count" do
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.reload
    assert_equal 22.0, ps.left_margin_mm.to_f
    assert_equal 18.0, ps.top_margin_mm.to_f
    assert_equal 28.0, ps.bottom_margin_mm.to_f
    assert_equal 3.0,  ps.binding_margin_mm.to_f
    assert_equal 23,   ps.body_line_count
  end

  test "A4 gets the two-anchor body_line_count (40) and proportional margins" do
    ps = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    ps.reload
    assert_equal 30.4, ps.left_margin_mm.to_f
    assert_equal 40,   ps.body_line_count
  end

  test "explicitly set margin is preserved (not clobbered)" do
    ps = @theme.paper_sizes.create!(size_name: "X", width_mm: 152, height_mm: 225, top_margin_mm: 99)
    assert_equal 99.0, ps.reload.top_margin_mm.to_f      # captured as overridden -> skipped
    assert_equal 22.0, ps.left_margin_mm.to_f            # left still generated
  end

  test "regenerate is idempotent and honors overridden_fields" do
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.update!(left_margin_mm: 12); ps.mark_overridden(:left_margin_mm)
    Design::DefaultGenerator.call(ps); ps.reload
    assert_equal 12.0, ps.left_margin_mm.to_f            # user value wins
    assert_equal 18.0, ps.top_margin_mm.to_f            # others recomputed, unchanged
  end
end
```

- [ ] **Step 2: Run it; verify it FAILS** (margins still at DB defaults / no generator).

- [ ] **Step 3: Implement `DefaultGenerator` (layout half) + the trigger**

`DG/app/services/design/default_generator.rb`:
```ruby
module Design
  class DefaultGenerator
    def self.call(paper_size) = new(paper_size).call

    def initialize(paper_size) = @paper_size = paper_size

    def call
      fill_layout
      @paper_size.document_designs.each { |dd| generate_headings_for(dd) }   # no-op until Task 4
      @paper_size
    end

    def fill_layout
      m = GenerationRules.margins_for(@paper_size.width_mm, @paper_size.height_mm)
      assigns = {
        left_margin_mm:    m[:left],  top_margin_mm:    m[:top],
        right_margin_mm:   m[:right], bottom_margin_mm: m[:bottom],
        binding_margin_mm: m[:binding],
        body_line_count:   GenerationRules.body_line_count_for(@paper_size.height_mm)
      }
      assigns.reject! { |attr, _| @paper_size.overridden?(attr) }
      @paper_size.update_columns(assigns) if assigns.any?
    end

    # Implemented in Task 4.
    def generate_headings_for(document_design) = nil
  end
end
```
> Uses `update_columns` (skips validations/callbacks) — safe (values are valid) and avoids re-entrant saves inside `after_create`.

In `DG/app/models/design/paper_size.rb`, add after the `before_create`:
```ruby
    after_create { Design::DefaultGenerator.call(self) }
```

- [ ] **Step 4: Run the test; verify it PASSES.** Also re-run `bin/rails test test/models/design/overridable_test.rb` (still green).

- [ ] **Step 5: Commit**
```bash
git add app/services/design/default_generator.rb app/models/design/paper_size.rb test/services/design/default_generator_test.rb
git commit -m "feat(theme-gen): DefaultGenerator fills paper-size layout on create"
```

---

## Task 4 — Heading overrides + DocumentDesign trigger

**Files:** Modify `DG/app/services/design/default_generator.rb`; modify `DG/app/models/design/document_design.rb`; extend `DG/test/services/design/default_generator_test.rb`.

- [ ] **Step 1: Add failing tests** (append to `default_generator_test.rb`):
```ruby
  # Helper: the gem doesn't seed base styles, so create the ones we assert on.
  def base!(name, size) = @theme.base_paragraph_styles.create!(name: name, font_size: size)

  test "doc_type gets scaled overrides ONLY for its relevant heading styles" do
    base!("title", 24); base!("subtitle", 18); base!("author", 7); base!("body", 9.5)
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "title_page")
    sizes = dd.paragraph_styles.index_by(&:name).transform_values { |s| s.font_size&.to_f }
    assert_equal 18.0, sizes["title"]      # 24 × 0.75
    assert_equal 13.5, sizes["subtitle"]   # 18 × 0.75
    assert_equal 6.0,  sizes["author"]     # 7 × 0.75 = 5.25 -> floor 6.0
    assert_nil   sizes["body"]             # body is not heading-scaled -> no override created
  end

  test "inside_cover scales only cover_* styles" do
    base!("cover_title", 24); base!("cover_body", 10); base!("title", 24)
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "inside_cover")
    names = dd.paragraph_styles.pluck(:name)
    assert_includes names, "cover_title"
    refute_includes names, "cover_body"   # not scaled
    refute_includes names, "title"        # not relevant to inside_cover
  end

  test "heading regenerate honors an overridden font_size" do
    base!("title", 24)
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "title_page")
    ov = dd.paragraph_styles.find_by!(name: "title")
    ov.update!(font_size: 99); ov.mark_overridden(:font_size)
    Design::DefaultGenerator.call(ps)
    assert_equal 99.0, ov.reload.font_size.to_f   # user value wins
  end
```

- [ ] **Step 2: Run; verify the new tests FAIL** (no overrides created yet).

- [ ] **Step 3: Implement `generate_headings_for` + the DocumentDesign trigger**

Replace the stub in `default_generator.rb`:
```ruby
    def generate_headings_for(document_design)
      theme  = @paper_size.theme
      height = @paper_size.height_mm
      scaled = GenerationRules.styles_for(document_design.doc_type) & GenerationRules::HEADING_SCALED_STYLES
      scaled.each do |name|
        base = theme.base_paragraph_styles.find_by(name: name)
        next unless base&.font_size
        override = document_design.override_for(name)
        next if override.overridden?(:font_size)
        override.update_columns(font_size: GenerationRules.scaled_size(base.font_size, height))
      end
    end
```
> `find_by` (not `find_by!`) — if a host theme is missing a base style, skip rather than raise. `override_for` is idempotent.

Add a class entry-point for the per-document trigger (top of `DefaultGenerator`):
```ruby
    def self.call_for(document_design)
      new(document_design.paper_size).generate_headings_for(document_design)
    end
```

In `DG/app/models/design/document_design.rb` (class body):
```ruby
    after_create { Design::DefaultGenerator.call_for(self) }
```

- [ ] **Step 4: Run; verify all DefaultGenerator tests PASS.**

- [ ] **Step 5: Run the full gem suite** — `bin/rails test`. Confirm **0 new failures** (existing model/service/component tests stay green; a pre-existing `DesignTailwindBuildFreshnessTest` failure, if it reappears, is unrelated). Heads-up: any existing test that creates a `PaperSize` now also runs generation — if one asserts old default margins, update it to the computed values (note such changes in the commit).

- [ ] **Step 6: Commit**
```bash
git add app/services/design/default_generator.rb app/models/design/document_design.rb test/services/design/default_generator_test.rb
git commit -m "feat(theme-gen): per-doc_type heading-size overrides + triggers"
```

---

## Task 5 — book_design host integration (migration + override wiring + regenerate)

**Files:** Create `BD/db/migrate/<ts>_add_overridden_fields_to_design.rb`; modify `BD/app/controllers/paper_sizes_controller.rb` (+ the paragraph-style controller). Pin the new gem revision afterward.

> **DB SAFETY:** in `BD`, the ONLY permitted DB command is additive `bin/rails db:migrate`. Never run `db:reset`/`db:drop`/`db:setup`/`db:seed`/`bin/setup` — BD holds real data.

- [ ] **Step 1: Pin BD to the new gem HEAD** (so the models have the concern/columns). Push the gem `main` first, then set `BD/Gemfile.lock`’s `design` revision to the new gem SHA (manual edit, no `bundle`), per the project’s push-then-pin convention.

- [ ] **Step 2: Add the migration**

`BD/db/migrate/<ts>_add_overridden_fields_to_design.rb` (use a real timestamp):
```ruby
class AddOverriddenFieldsToDesign < ActiveRecord::Migration[8.1]
  def change
    add_column :design_paper_sizes, :overridden_fields, :json, null: false, default: []
    add_column :design_paragraph_styles, :overridden_fields, :json, null: false, default: []
  end
end
```
Run (additive — allowed): `cd /Users/mskim/Development/book/book_design && bin/rails db:migrate`. Expected: two columns added; `db/schema.rb` updated.

- [ ] **Step 3: Write a failing host integration test**

`BD/test/controllers/paper_sizes_override_test.rb`:
```ruby
require "test_helper"

class PaperSizesOverrideTest < ActionDispatch::IntegrationTest
  setup do
    @theme = Design::Theme.create!(name: "H #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "user-edited margin is marked overridden so regenerate preserves it" do
    patch theme_paper_size_path(@theme, @ps), params: { paper_size: { top_margin_mm: 40 } }
    assert @ps.reload.overridden?(:top_margin_mm)
    Design::DefaultGenerator.call(@ps)
    assert_equal 40.0, @ps.reload.top_margin_mm.to_f
  end
end
```

- [ ] **Step 4: Run it; verify it FAILS** (update doesn’t mark overridden yet).

- [ ] **Step 5: Wire `mark_overridden_from_changes` into the update path**

In `BD/app/controllers/paper_sizes_controller.rb#update`, after a successful `@paper_size.update(...)`:
```ruby
  def update
    if @paper_size.update(paper_size_params)
      @paper_size.mark_overridden_from_changes(Design::PaperSize::GENERATABLE_FIELDS)
      auto_export_book_design(@theme)
      redirect_to theme_paper_size_path(@theme, @paper_size), notice: "Paper size updated."
    else
      render Pages::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size),
             layout: "application", status: :unprocessable_entity
    end
  end
```
Do the equivalent in the paragraph-style update/override action(s) that can change `font_size` (call `mark_overridden_from_changes(Design::ParagraphStyle::GENERATABLE_FIELDS)` after the successful update). Find them in `BD/app/controllers/` (paragraph styles controller).

- [ ] **Step 6: Run the test; verify it PASSES.**

- [ ] **Step 7: Add a "Regenerate defaults" action** (exposes the service):

In `BD/config/routes.rb`, add `post :regenerate, on: :member` to `resources :paper_sizes`. In the controller:
```ruby
  def regenerate
    Design::DefaultGenerator.call(@paper_size)
    auto_export_book_design(@theme)
    redirect_to edit_theme_paper_size_path(@theme, @paper_size), notice: "Defaults regenerated."
  end
```
(Add `:regenerate` to the `before_action :set_paper_size` list. A button on the edit form is optional UI polish — wire the route + action now.)

- [ ] **Step 8: Run BD tests** — `bin/rails test test/controllers/paper_sizes_override_test.rb test/controllers/paper_sizes_controller_test.rb`. Green.

- [ ] **Step 9: Commit** (BD), then push gem + BD per the push-then-pin convention.
```bash
cd /Users/mskim/Development/book/book_design
git add db/migrate/ db/schema.rb config/routes.rb app/controllers/paper_sizes_controller.rb app/controllers/<paragraph_styles_controller>.rb test/controllers/paper_sizes_override_test.rb
git commit -m "feat(theme-gen): wire override-tracking + regenerate into paper-size editing"
```

---

## Final verification
- [ ] `DG`: `bin/rails test` — generator/rules/concern green; 0 new failures.
- [ ] `BD`: new paper size created via the form gets proportional margins + blc; editing a margin then "Regenerate defaults" preserves the edit; other fields recompute.
- [ ] `book_write` unaffected at runtime (it pins the gem; the migration is additive and must be applied there too before its paper-size creation runs generation — note for BW rollout, out of scope here).

## Notes / gotchas
- The gem does **not** seed the 34 base styles — gem tests create the base styles they assert on (`base!` helper).
- `before_create` capture protects explicit create-time values; the generator (`update_columns`) never marks fields overridden — only user edits (controller `mark_overridden_from_changes`) and explicit creates do.
- `body_line_count` regeneration **rewrites** existing un-overridden values (author-confirmed): 국판 21→19, A4 30→40. Margins are unchanged by regeneration (ratio reproduces current data).
- `quote` scales for body-bearing doc_types (author-confirmed).
- Don’t scale body/list/caption/table/running/`*_body` styles.
