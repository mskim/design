# Themes Area Port — Implementation Plan (Sub-project #1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port book_design's Themes-area UI into the gem studio — flat-grid rich index cards with generated previews, a show page grouped Frontmatter/Bodymatter/Rearmatter, and theme create/edit (which the gem lacks).

**Architecture:** Add matter-group constants + `grouped_by_matter` to `Design::DocumentDesign`; a generate-first preview helper on `Design::Views::Base`; a `Design::Views::Themes::Form` + `new/create/edit/update` controller actions + routes; rewrite `Themes::Index` (flat grid, rich cards) and enrich `Themes::Show` (grouped sections). Host-only tools stay host (surfaced via the #0 action registry); book_design drops its "New theme" registration.

**Tech Stack:** Rails 8.1 engine, Phlex 2.4 components, RubyUI, `Design::PreviewService` (PDF→JPG), Minitest, scoped Tailwind.

**Spec:** `design/docs/superpowers/specs/2026-06-24-themes-area-port-design.md`

**Repo:** `DG = /Users/mskim/Development/ruby/gems/design` (gem, branch `main`) — Tasks 1–5. `BD = /Users/mskim/Development/book/book_design` — Task 6.

**Conventions (verified):**
- Gem components are Phlex (`Design::Views::Base`, includes Routes/ButtonTo/TurboFrameTag/RubyUI). Host routes resolve via `helpers.main_app.*`; gem engine routes via `helpers.<route>_path`. Studio pages render inside `shell(title:, action_slot:, action_context:) do …body… end` (from #0).
- `Design::PreviewService.new(dd, paper_size: ps).generate` → `{ success:, jpg_path:, … }`; it shells out to doc_processor_rb + ImageMagick (cached by content fingerprint). **Tests MUST stub `.generate`** so they don't shell out.
- `preview_jpg_theme_paper_size_document_design_path(theme, ps, dd, t:)` is a real engine route.
- `Design::Theme` columns: `name, description, locale, base_body_font, base_body_font_size, base_heading_font`; `AVAILABLE_FONTS` constant; `validates :locale, inclusion: %w[ko en ja zh]`; `default_paper_size`, `editable_by?(user)`, `system?`.
- `Design::DocumentDesign` has `DOC_TYPE_ORDER` + `by_reading_order` (prior fix); `COVER_PANEL_TYPES`.
- Minitest only. Commit to `main`. Do NOT push. Leave `Gemfile.lock` unstaged. Tests mirror `test/components/design/*` (render via `.call` + `define_singleton_method` stubs) and `test/controllers/design/*` (integration).

**Test mechanics (CRITICAL — used by several tasks):**
- **Editability:** a theme created without a `user:` is `system?` and the dummy app sets `authoring = false`, so `editable_by?` is **false** → `edit`/`update`/`edit_theme_button` are forbidden/hidden. Any test that exercises edit/update or asserts the native "Edit Theme" button MUST create an **owned custom theme + sign in**: `Design::Theme.create!(name: …, locale: "ko", user: users(:david))` and `sign_in :david` in `setup` (mirror `test/controllers/design/themes_controller_test.rb` + `themes_show_editable_chips_test.rb`). `Design.current_user` reads `CurrentDesigner` (set by `sign_in`). `create` itself is NOT gated, so plain create tests don't need an owner.
- **Stubbing `PreviewService`** (Minitest 6 here has NO `Object#stub`/`stub_any_instance`/Mocha): use the repo's established **factory-swap** pattern from `test/controllers/design/document_designs_preview_test.rb`:
  ```ruby
  def stub_preview_service(fake)
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original)
  end
  # usage: fake = Object.new; def fake.generate = { success: true }
  #        stub_preview_service(fake) { … render … }
  ```
  Every preview-touching test (Task 2; Task 4/5 for themes WITH a chapter doc; updated `themes_controller_test.rb` cases) uses this — do NOT use `stub_any_instance`/`define_method(:generate)`. The fake's `generate` returning `{ success: true }` (no `jpg_path`) is fine — `design_preview_img` only reads `[:success]`.

---

## File Structure

**`DG` (gem):**
- Modify `app/models/design/document_design.rb` — matter-group constants + `grouped_by_matter`.
- Modify `app/components/design/views/base.rb` — `design_preview_img` helper.
- Create `app/components/design/views/themes/form.rb` — `Design::Views::Themes::Form`.
- Modify `app/controllers/design/themes_controller.rb` — `new`/`create`/`edit`, extend `update` + `theme_params`, flat `index`.
- Modify `config/routes.rb` — add `new`/`create`/`edit` to `themes`.
- Rewrite `app/components/design/views/themes/index.rb` — flat grid + rich cards.
- Modify `app/components/design/views/themes/show.rb` — grouped sections + generated previews.
- Modify `config/locales/{ko,en}.yml` — any new keys (form labels, matter-section titles).
- Tests under `test/models/design/`, `test/components/design/`, `test/controllers/design/`.

**`BD` (host) — Task 6:**
- Modify `config/initializers/design.rb` — drop the `New theme` descriptor.

---

## Task 1 — Matter groups + `grouped_by_matter` (DocumentDesign)

**Files:** Modify `DG/app/models/design/document_design.rb`; create `DG/test/models/design/grouped_by_matter_test.rb`.

> Groups taken from book_design's `pages/themes/show.rb` (its themes-show grouping, which differs slightly from the paper-sizes one). All 17 interior doc_types land in a group; `other:` is the safety bucket.

- [ ] **Step 1: Write the failing test** `DG/test/models/design/grouped_by_matter_test.rb`:
```ruby
require "test_helper"

class Design::GroupedByMatterTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "G #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "partitions into front/body/rear in reading order, unknowns to other" do
    %w[appendix chapter title_page copyright toc].each { |t| @ps.document_designs.create!(doc_type: t) }
    g = Design::DocumentDesign.grouped_by_matter(@ps.document_designs)
    assert_equal %w[title_page copyright toc], g[:frontmatter].map(&:doc_type)
    assert_equal %w[chapter], g[:bodymatter].map(&:doc_type)
    assert_equal %w[appendix], g[:rearmatter].map(&:doc_type)
    assert_equal [], g[:other].map(&:doc_type)
  end

  test "a doc_type in no matter group lands in other" do
    # front_page is a cover-panel type, in none of the three matter groups
    @ps.document_designs.create!(doc_type: "front_page")
    g = Design::DocumentDesign.grouped_by_matter(@ps.document_designs)
    assert_equal %w[front_page], g[:other].map(&:doc_type)
  end
end
```

- [ ] **Step 2: Run it; verify it FAILS** — `cd /Users/mskim/Development/ruby/gems/design && bin/rails test test/models/design/grouped_by_matter_test.rb` (no `grouped_by_matter`).

- [ ] **Step 3: Implement.** In `app/models/design/document_design.rb`, after the `DOC_TYPE_ORDER` / `by_reading_order` block, add:
```ruby
    # Reading-matter groups for the theme show page (mirrors book_design's grouping).
    FRONTMATTER = %w[title_page inside_cover blank_page copyright toc foreword prologue dedication thanks information].freeze
    BODYMATTER  = %w[chapter poem part_cover document_cover].freeze
    REARMATTER  = %w[epilogue appendix help].freeze

    # Partition designs into ordered matter groups; doc_types in none land in :other.
    def self.grouped_by_matter(designs)
      ordered = by_reading_order(designs)
      {
        frontmatter: ordered.select { |dd| FRONTMATTER.include?(dd.doc_type) },
        bodymatter:  ordered.select { |dd| BODYMATTER.include?(dd.doc_type) },
        rearmatter:  ordered.select { |dd| REARMATTER.include?(dd.doc_type) },
        other:       ordered.reject { |dd| (FRONTMATTER + BODYMATTER + REARMATTER).include?(dd.doc_type) }
      }
    end
```
> `by_reading_order` returns an Array sorted by `DOC_TYPE_ORDER`; the `select`s preserve that order within each group.

- [ ] **Step 4: Run the test; verify it PASSES.**

- [ ] **Step 5: Commit:**
```bash
cd /Users/mskim/Development/ruby/gems/design
git add app/models/design/document_design.rb test/models/design/grouped_by_matter_test.rb
git commit -m "feat(themes): DocumentDesign.grouped_by_matter (front/body/rear/other)"
```

---

## Task 2 — `design_preview_img` generate-first helper (Base)

**Files:** Modify `DG/app/components/design/views/base.rb`; create `DG/test/components/design/design_preview_img_test.rb`.

- [ ] **Step 1: Write the failing test** `DG/test/components/design/design_preview_img_test.rb`:
```ruby
require "test_helper"

class Design::DesignPreviewImgTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "P #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  class Probe < Design::Views::Base
    def initialize(theme:, ps:, dd:) = (@theme = theme; @ps = ps; @dd = dd)
    def view_template
      design_preview_img(@theme, @ps, @dd, img_class: "thumb") { plain "NOPREVIEW" }
    end
  end

  def render
    c = Probe.new(theme: @theme, ps: @ps, dd: @dd)
    # stub the engine route helper used inside the helper
    c.define_singleton_method(:helpers) do
      o = Object.new
      def o.preview_jpg_theme_paper_size_document_design_path(*, **) = "/preview.jpg"
      o
    end
    c.call
  end

  # factory-swap stub (the repo pattern — see document_designs_preview_test.rb + Conventions)
  def stub_preview_service(success:)
    fake = Object.new
    fake.define_singleton_method(:generate) { { success: success } }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original)
  end

  test "renders the img when generate succeeds" do
    stub_preview_service(success: true) do
      html = render
      assert_includes html, %(src="/preview.jpg")
      assert_includes html, %(class="thumb")
      refute_includes html, "NOPREVIEW"
    end
  end

  test "renders the fallback when generate fails" do
    stub_preview_service(success: false) do
      html = render
      assert_includes html, "NOPREVIEW"
      refute_includes html, "<img"
    end
  end
end
```
Run → FAIL (`design_preview_img` undefined).

- [ ] **Step 2: Run it; verify it FAILS.**

- [ ] **Step 3: Implement** in `app/components/design/views/base.rb` (add to the class):
```ruby
      # Generate (cached) the preview for a document design and emit an <img>; if
      # generation fails or args are missing, yield the fallback block (e.g. a
      # placeholder). Generation shells out to PreviewService (matches book_design's
      # generate-on-render); the PreviewService fingerprint cache skips unchanged designs.
      # NOTE: no `t:` cache-buster — that keeps the JPG URL stable (so existing
      # `img[src=?]` assertions hold, and the browser caches the thumbnail). A
      # regenerated JPG may briefly show stale in-browser; adding a fingerprint-based
      # buster is part of the deferred preview-perf pass (spec Decision 7).
      def design_preview_img(theme, paper_size, document_design, img_class:, &fallback)
        ok = paper_size && document_design &&
             Design::PreviewService.new(document_design, paper_size: paper_size).generate[:success]
        if ok
          img(src: helpers.preview_jpg_theme_paper_size_document_design_path(theme, paper_size, document_design),
              alt: document_design.doc_type, class: img_class)
        elsif fallback
          fallback.call
        end
      end
```

- [ ] **Step 4: Run the test; verify it PASSES.**

- [ ] **Step 5: Commit:**
```bash
git add app/components/design/views/base.rb test/components/design/design_preview_img_test.rb
git commit -m "feat(themes): design_preview_img — generate-first preview helper"
```

---

## Task 3 — Theme Form + new/create/edit/update + routes

**Files:** Create `DG/app/components/design/views/themes/form.rb`; modify `DG/app/controllers/design/themes_controller.rb`, `DG/config/routes.rb`, `config/locales/{ko,en}.yml`; create `DG/test/controllers/design/themes_form_test.rb`.

- [ ] **Step 1: Write the failing test** `DG/test/controllers/design/themes_form_test.rb`:
```ruby
require "test_helper"

class Design::ThemesFormTest < ActionDispatch::IntegrationTest
  setup { sign_in :david }   # editability needs a signed-in designer (see Conventions)

  test "new renders the form" do
    get design.new_theme_path
    assert_response :success
    assert_select "form"
    assert_includes response.body, %(name="theme[name]")
  end

  test "create with valid params makes a theme and redirects to show" do
    assert_difference -> { Design::Theme.count }, 1 do
      post design.themes_path, params: { theme: { name: "NewTheme #{SecureRandom.hex(3)}", locale: "ko" } }
    end
    assert_response :redirect
  end

  test "create with invalid params re-renders the form (422)" do
    post design.themes_path, params: { theme: { name: "", locale: "ko" } }
    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "edit + update round-trips fonts and locale (owned custom theme)" do
    theme = Design::Theme.create!(name: "E #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    get design.edit_theme_path(theme)
    assert_response :success
    patch design.theme_path(theme), params: { theme: { base_body_font_size: 11.5, locale: "en" } }
    assert_equal 11.5, theme.reload.base_body_font_size.to_f
    assert_equal "en", theme.locale
  end
end
```
> Mirror the exact `sign_in`/fixture pattern of `test/controllers/design/themes_controller_test.rb` (it signs in + uses `users(:david)`). The edit/update theme MUST be owned (`user: users(:david)`) — a `user_id`-less theme is `system?` and not editable when the dummy's `authoring = false`. Run → FAIL (no `new_theme_path` route).

- [ ] **Step 2: Run it; verify it FAILS.**

- [ ] **Step 3: Add the routes.** In `DG/config/routes.rb`, change the `themes` resource line to include new/create/edit:
```ruby
  resources :themes, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
```

- [ ] **Step 4: Implement the Form** `DG/app/components/design/views/themes/form.rb` (ported from book_design's `Pages::Themes::Form`, adapted to render inside the studio shell + use I18n labels):
```ruby
module Design
  module Views
    module Themes
      class Form < Design::Views::Base
        def initialize(theme:)
          @theme = theme
        end

        def view_template
          shell(title: @theme.persisted? ? I18n.t("design.themes.edit_title") : I18n.t("design.themes.new_title")) do
            div(class: "max-w-2xl mx-auto p-8") do
              render_errors
              render_form
            end
          end
        end

        private

        def render_form
          url = @theme.persisted? ? helpers.theme_path(@theme) : helpers.themes_path
          method = @theme.persisted? ? :patch : :post
          form(action: url, method: :post, class: "space-y-6") do
            input(type: :hidden, name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: :hidden, name: "_method", value: method.to_s) if method == :patch

            section(I18n.t("design.themes.identity")) do
              field(I18n.t("design.themes.name_label"), :name, required: true)
              field(I18n.t("design.themes.description_label"), :description, type: :textarea)
              select_field(I18n.t("design.themes.locale_label"), :locale, %w[ko en ja zh])
            end
            section(I18n.t("design.themes.default_fonts")) do
              font_select_field(I18n.t("design.themes.body_font"), :base_body_font)
              field(I18n.t("design.themes.body_font_size"), :base_body_font_size, type: :number, step: "0.1")
              font_select_field(I18n.t("design.themes.heading_font"), :base_heading_font)
            end
            div(class: "flex gap-3") do
              render RubyUI::Button.new(variant: :primary, type: :submit) do
                @theme.persisted? ? I18n.t("design.themes.update_button") : I18n.t("design.themes.create_button")
              end
              a(href: helpers.themes_path) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.shared.cancel") } }
            end
          end
        end

        def section(title, &block)
          div(class: "space-y-4") do
            h3(class: "text-lg font-medium border-b pb-2") { title }
            yield
          end
        end

        def field(label_text, attr, type: :text, **opts)
          div do
            label(class: "block text-sm font-medium mb-1") { label_text }
            if type == :textarea
              textarea(name: "theme[#{attr}]", rows: 3,
                       class: "w-full rounded-md border border-input bg-background px-3 py-2 text-sm") { @theme.send(attr) }
            else
              input(type: type, name: "theme[#{attr}]", value: @theme.send(attr).to_s,
                    class: "w-full rounded-md border border-input bg-background px-3 py-2 text-sm", **opts)
            end
          end
        end

        def font_select_field(label_text, attr)
          current = @theme.send(attr).to_s
          div do
            label(class: "block text-sm font-medium mb-1") { label_text }
            select(name: "theme[#{attr}]", class: "w-full rounded-md border border-input bg-background px-3 py-2 text-sm") do
              option(value: "", selected: current.empty?) { "— default —" }
              Design::Theme::AVAILABLE_FONTS.each { |f| option(value: f, selected: current == f) { f } }
            end
          end
        end

        def select_field(label_text, attr, options)
          div do
            label(class: "block text-sm font-medium mb-1") { label_text }
            select(name: "theme[#{attr}]", class: "w-full rounded-md border border-input bg-background px-3 py-2 text-sm") do
              options.each { |opt| option(value: opt, selected: @theme.send(attr) == opt) { opt } }
            end
          end
        end

        # NOTE: the gem has NO RubyUI::Alert (only badge/button/card/tabs) — use a plain div.
        def render_errors
          return unless @theme.errors.any?
          div(class: "mb-4 rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-700") do
            ul(class: "list-disc pl-4") { @theme.errors.full_messages.each { |m| li { m } } }
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Implement the controller actions.** In `DG/app/controllers/design/themes_controller.rb`:
- Add `:new` is not in `set_theme`'s `only:` (it has no id); add `:edit` to `set_theme`'s `only:` list.
- Add actions:
```ruby
    def new
      render Design::Views::Themes::Form.new(theme: Design::Theme.new(locale: I18n.locale.to_s))
    end

    def create
      @theme = Design::Theme.new(theme_params)
      if @theme.save
        redirect_to theme_path(@theme), notice: t("design.themes.created_notice", name: @theme.name)
      else
        render Design::Views::Themes::Form.new(theme: @theme), status: :unprocessable_entity
      end
    end

    def edit
      return head :forbidden unless @theme.editable_by?(Design.current_user)
      render Design::Views::Themes::Form.new(theme: @theme)
    end
```
- Change `set_theme`'s `only:` to include `:edit`: `before_action :set_theme, only: [ :show, :edit, :update, :destroy, :clone, :generate_sizes ]`.
- Extend `theme_params` to the full set:
```ruby
    def theme_params
      params.require(:theme).permit(:name, :description, :locale, :base_body_font, :base_body_font_size, :base_heading_font)
    end
```
> `update` already uses `theme_params` + `editable_by?`; the wider permit makes it a full update. Its redirect/notice can stay, or switch to `theme_path(@theme)` — keep existing behavior to avoid breaking the rename test; if a rename test asserts `renamed_notice`, leave it.

- [ ] **Step 6: Add i18n keys** to `config/locales/ko.yml` + `en.yml` under `design.themes`: `edit_title`, `new_title`, `identity`, `name_label`, `description_label`, `locale_label`, `default_fonts`, `body_font`, `body_font_size`, `heading_font`, `update_button`, `create_button`, `created_notice` (with `%{name}`). (Korean + English; **both files, identical keys** — `test/i18n/locale_parity_test.rb` enforces this.) NOTE: `design.shared.cancel` already exists (from the localization sub-project) — the Form **reuses** it; do not re-add.

- [ ] **Step 7: Run the test; verify it PASSES.** Then run `bin/rails test test/i18n/locale_parity_test.rb` (keys mirrored).

- [ ] **Step 8: Commit:**
```bash
git add app/components/design/views/themes/form.rb app/controllers/design/themes_controller.rb config/routes.rb config/locales/ test/controllers/design/themes_form_test.rb
git commit -m "feat(themes): theme create/edit Form + new/create/edit/update + routes"
```

---

## Task 4 — Rewrite `Themes::Index` (flat grid + rich cards)

**Files:** Modify `DG/app/controllers/design/themes_controller.rb` (index), rewrite `DG/app/components/design/views/themes/index.rb`; update/extend `DG/test/components/design/...` + an integration test.

- [ ] **Step 1: Write/extend the failing test.** Add `DG/test/controllers/design/themes_index_flat_test.rb`:
```ruby
require "test_helper"

class Design::ThemesIndexFlatTest < ActionDispatch::IntegrationTest
  test "index is a single flat grid with a New theme link and rich cards" do
    t = Design::Theme.create!(name: "FlatT #{SecureRandom.hex(3)}", locale: "ko")
    get design.themes_path
    assert_response :success
    assert_select "a[href=?]", design.new_theme_path        # gem-native New theme
    assert_includes response.body, t.name
    assert_includes response.body, t.locale.upcase          # locale badge
    assert_select ".themes-grid", 1                          # ONE grid (no system/custom split)
    assert_not_includes response.body, "design-studio__header"  # (already gone since #0)
  end
end
```
> A populated theme with a chapter doc would generate a preview; to keep this test off PDF rendering, assert on the structure (grid, New theme link, name, badge) for an empty theme (no chapter → no preview img, no shell-out). Run → FAIL (current index is the 2-col split, no New theme link).

- [ ] **Step 2: Run it; verify it FAILS.**

- [ ] **Step 3: Flatten the controller index.** In `themes_controller.rb#index`:
```ruby
    def index
      @themes = Design::Theme.order(:name)
      render Design::Views::Themes::Index.new(themes: @themes)
    end
```

- [ ] **Step 4: Rewrite the Index component** `app/components/design/views/themes/index.rb` — flat grid + rich card (ported from book_design's `render_theme_card`, using `design_preview_img` (Task 2) for the preview and `RubyUI::Card`/`Badge`). The component now takes `themes:`. Render inside the existing `shell(title:, action_slot: :themes_index)`. Body: a header row with a gem-native **"New theme"** button (`a href: helpers.new_theme_path`) + the grid `div(class: "themes-grid grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4")`. Each card:
```ruby
        def theme_card(theme)
          default_ps = theme.default_paper_size
          chapter_dd = default_ps&.document_designs&.find_by(doc_type: "chapter")
          a(href: helpers.theme_path(theme), class: "theme-card block group") do
            RubyUI::Card(class: "overflow-hidden hover:shadow-md transition-shadow") do
              if chapter_dd
                div(class: "h-40 bg-gray-50 flex items-center justify-center overflow-hidden border-b") do
                  design_preview_img(theme, default_ps, chapter_dd, img_class: "h-full object-contain") {}
                end
              end
              div(class: "p-4") do
                div(class: "flex items-start justify-between mb-2") do
                  div do
                    h3(class: "text-lg font-semibold group-hover:text-blue-600 transition-colors") { theme.name }
                    p(class: "text-sm text-muted-foreground") { theme.base_body_font }
                  end
                  RubyUI::Badge(variant: :blue, size: :sm) { theme.locale.upcase }
                end
                paper_size_badges(theme, default_ps)
                div(class: "flex items-center gap-3 text-xs text-muted-foreground mt-2") do
                  span { I18n.t("design.themes.sizes_count", count: theme.paper_sizes.count) }
                  span { I18n.t("design.themes.doc_types_count", count: theme.document_designs.count) }
                end
              end
            end
          end
        end
```
Add `paper_size_badges` (★ for default, like book_design). Keep the per-theme clone/rename/delete affordances available somewhere sensible (e.g. the show page already has clone; for the index card, you MAY drop the inline rename/clone forms in favor of the card linking to show — confirm with existing tests; if a test asserts the inline rename/clone on the index, keep them or move the assertion). The gem-native "New theme" button replaces book_design's host one.
> **i18n:** add `design.themes.sizes_count` + `design.themes.doc_types_count` (with `%{count}`) to BOTH `ko.yml` + `en.yml` (parity test). The Korean uses count interpolation, e.g. `"판형 %{count}개"` / `"문서 유형 %{count}개"`.

- [ ] **Step 5: Run the test; verify it PASSES.** Then the **full suite** `bin/rails test 2>&1 | tail -8`. **These existing tests WILL break — update each (flag as intended redesign, not silent breakage):**
  - `test/controllers/design/themes_controller_test.rb` — its `index` test (`:60-69`) asserts a preview `img[src=?]` (now generate-first → wrap with `stub_preview_service(success: true)`; URL still matches since we dropped `t:`) and its `.preview-empty` test (`:71-80` — keep emitting `.preview-empty` in the card's fallback, or update the assertion).
  - `test/components/design/themes_index_phlex_test.rb` — asserts `.themes-grid [data-theme-card]` and the old constructor (`system_themes:/custom_themes:` → now `themes:`); update the render call + structure assertions.
  - `test/controllers/design/themes_index_redesign_test.rb` — asserts `section[data-themes=system]` + inline clone/rename forms (the 2-col split is gone); rewrite to the flat grid.
  - `test/controllers/design/studio_shell_test.rb` — asserts `.themes-grid` count (should still pass — one grid — but verify).
  Rebuild `design.css` if new classes were added (`bin/rails runner '…tailwind build…'` per the #0 plan) and keep `DesignTailwindBuildFreshnessTest` green.

- [ ] **Step 6: Commit:**
```bash
git add app/components/design/views/themes/index.rb app/controllers/design/themes_controller.rb app/assets/builds/design.css config/locales/ test/controllers/design/themes_index_flat_test.rb <updated tests>
git commit -m "feat(themes): flat grid index with rich cards + generated previews"
```

---

## Task 5 — Enrich `Themes::Show` (grouped sections + generated previews)

**Files:** Modify `DG/app/components/design/views/themes/show.rb`; modify the controller `show` to pass grouped designs (or keep passing the list and group in the view); update tests.

- [ ] **Step 1: Write the failing test** `DG/test/controllers/design/themes_show_grouped_test.rb`:
```ruby
require "test_helper"

class Design::ThemesShowGroupedTest < ActionDispatch::IntegrationTest
  setup { sign_in :david }   # the "Edit Theme" button is gated on editability

  test "show groups interior doc designs into matter sections in order" do
    t = Design::Theme.create!(name: "ShowG #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    ps = t.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    %w[appendix chapter title_page].each { |d| ps.document_designs.create!(doc_type: d) }
    stub_preview_service(success: false) do   # avoid shelling out; cards fall back to placeholder
      get design.theme_path(t)
    end
    assert_response :success
    # the three section headings appear, Front before Body before Rear
    body = response.body
    assert_operator body.index(I18n.t("design.themes.frontmatter")), :<, body.index(I18n.t("design.themes.bodymatter"))
    assert_operator body.index(I18n.t("design.themes.bodymatter")), :<, body.index(I18n.t("design.themes.rearmatter"))
    assert_select "a[href=?]", design.edit_theme_path(t)   # native Edit Theme (owned + signed-in)
  end

  # factory-swap stub — copy the helper from Conventions / document_designs_preview_test.rb
  def stub_preview_service(success:)
    fake = Object.new
    fake.define_singleton_method(:generate) { { success: success } }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original)
  end
end
```
> The theme is owned + we `sign_in :david` so the "Edit Theme" button (gated on `editable_by?`) renders. `stub_preview_service` keeps the grouped cards off PDF rendering (they fall back to the placeholder). Run → FAIL (current show is a flat grid, no section headings, no native Edit link).

- [ ] **Step 2: Run it; verify it FAILS.**

- [ ] **Step 3: Enrich the Show component** `app/components/design/views/themes/show.rb`:
- Replace the flat `doc_grid`'s body with grouped sections: `Design::DocumentDesign.grouped_by_matter(@document_designs)` → for each of `[:frontmatter, :bodymatter, :rearmatter, :other]` with a non-empty list, render a section heading (`I18n.t("design.themes.#{key}")`, with `other` → a generic label) + a responsive grid of preview cards.
- Each card uses `design_preview_img(@theme, @selected_paper_size, dd, img_class: …) { placeholder }` for the thumbnail, linking to the doc-design edit (keep the existing `doc_card` link/edit behavior).
- Add a native **"Edit Theme"** button (`a href: helpers.edit_theme_path(@theme)`) in the header section (next to the existing clone button), shown when `@theme.editable_by?(current_user)`.
- Keep `header_section`, `size_selector` (paper-size tabs + turbo-frame), and `generate_sizes`.

- [ ] **Step 4: Add i18n keys** `design.themes.{frontmatter,bodymatter,rearmatter,other,edit_theme_button}` to both `ko.yml` + `en.yml`.

- [ ] **Step 5: Run the test; verify it PASSES.** Full suite `bin/rails test 2>&1 | tail -8`. **Existing show tests that break — update each (flag as intended):**
  - `test/controllers/design/themes_controller_test.rb` — its 4 show tests (`:82-124`) assert `[data-doc-grid] img` counts + bare `img[src=?]` (no `t:` — still matches) on a flat grid; the regrouped sections change the structure → wrap preview-asserting cases with `stub_preview_service(success: true)` and update the count/structure assertions to the grouped layout.
  - `test/controllers/design/themes_show_editable_chips_test.rb` — asserts the show page's editable chips/structure; verify it still holds after regrouping (its doc-type chips are about the PropertiesPanel/editor, likely unaffected, but run it).
  Rebuild `design.css` if classes changed; keep freshness green.

- [ ] **Step 6: Commit:**
```bash
git add app/components/design/views/themes/show.rb app/components/design/views/... config/locales/ app/assets/builds/design.css test/controllers/design/themes_show_grouped_test.rb <updated tests>
git commit -m "feat(themes): show page grouped by matter + generated previews + Edit Theme"
```

---

## Task 6 — book_design drops the host "New theme" registration

**Files:** Modify `BD/config/initializers/design.rb`; (optional) a test assertion.

> ⛔ DEV-DATA SAFETY: in book_design, ONLY `bin/rails test` (test DB). NEVER `db:*`.

- [ ] **Step 1: Remove the descriptor.** In `BD/config/initializers/design.rb`, in the `Design.config.actions.for(:themes_index)` block, **delete the `New theme` descriptor** (the gem now renders it natively). Keep Import / Generate / Style browser:
```ruby
  Design.config.actions.for(:themes_index) do
    [ { label: "Import",        path: main_app.import_themes_path,    method: :post },
      { label: "Generate",      path: main_app.generate_themes_path,  method: :post },
      { label: "Style browser", path: main_app.style_browser_path,    method: :get } ]
  end
```

- [ ] **Step 2: Update/confirm the host integration test.** If `BD/test/integration/studio_host_actions_test.rb` (or a themes-index variant) asserts a "New theme" host button, update it: the gem renders the native New-theme link, and the `:themes_index` host actions are now Import/Generate/Style-browser only. Run `cd /Users/mskim/Development/book/book_design && bin/rails test test/integration/studio_host_actions_test.rb`.

- [ ] **Step 3: Run book_design's full suite** — `bin/rails test 2>&1 | tail -8`. 0 new failures.

- [ ] **Step 4: Commit:**
```bash
cd /Users/mskim/Development/book/book_design
git add config/initializers/design.rb test/integration/studio_host_actions_test.rb
git commit -m "feat(themes): drop host New-theme action (gem provides it natively)"
```

---

## Final verification
- [ ] `DG`: `bin/rails test` — grouped_by_matter / preview-helper / form-CRUD / flat-index / grouped-show all green; CSS freshness green; locale parity green; 0 new failures.
- [ ] In book_design: `/design/themes` is a flat grid of rich cards (real previews on populated themes, e.g. Seoul); a gem-native "New theme" button works (create → show); `/design/themes/:id` shows Frontmatter/Bodymatter/Rearmatter sections + an "Edit Theme" button; host buttons (Import/Generate/Style-browser/Export/Generate-PDFs) still appear.
- [ ] book_write unaffected at runtime (renders the gem; no host buttons; New-theme/Edit work via gem routes).

## Notes / gotchas
- **Stub `PreviewService.generate` in tests** — it shells out (PDF + ImageMagick). Use the repo's stubbing convention (Minitest 6 has no `Object#stub`/Mocha; `define_method`/`define_singleton_method` with restore). Tests that render index/show cards for themes WITH a chapter doc must stub it; tests for empty themes don't trigger it.
- **Generate-on-render perf** is a known follow-up (Decision 7 in the spec) — don't add caching/async here.
- **Created themes are metadata-only** (no 34 base styles) — expected; real themes come from clone/host-generate.
- Rebuild `design.css` + keep `DesignTailwindBuildFreshnessTest` green whenever component classes change (Tasks 4, 5).
- i18n keys go in BOTH `ko.yml` + `en.yml` (parity test enforces).
- Match book_design's exact card/badge/section classes; no token authoring.
