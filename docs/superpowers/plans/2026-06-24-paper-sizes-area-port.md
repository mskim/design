# Paper-Sizes Area Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full paper-size create / edit / delete / regenerate to the `design` gem studio, reached from the theme show page, matching book_design's behaviour and field set.

**Architecture:** A single Phlex `Design::Views::PaperSizes::Form` (replacing the current `Edit`) serves both new and edit, switching action/method on `persisted?`. `Design::PaperSizesController` gains `new`/`create`/`destroy`/`regenerate` and a widened `update`; each write re-exports the baked theme DB and is guarded by the existing `ensure_theme_editable`. The model already supports everything (validations, `Overridable`, `after_create DefaultGenerator`) — no migration. The theme show page gets two entry-point links (＋New size, Edit).

**Tech Stack:** Rails engine, Phlex components, RubyUI (Button only — gem has **no** `RubyUI::Alert`), Minitest integration tests, `Design::Overridable`, `Design::DefaultGenerator`, `Design::ThemeDbExportService`.

**Spec:** `docs/superpowers/specs/2026-06-24-paper-sizes-area-port-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `config/routes.rb` | Add `new/create/destroy` + member `post :regenerate` to `paper_sizes` | Modify |
| `config/locales/ko.yml` / `en.yml` | Add the new `design.paper_sizes.*` keys | Modify |
| `app/components/design/views/paper_sizes/form.rb` | One component for new + edit (Page Size / Margins / Body Settings; edit-only base-styles list + Regenerate/Delete) | Create |
| `app/components/design/views/paper_sizes/edit.rb` | Folded into `Form` | Delete |
| `app/controllers/design/paper_sizes_controller.rb` | `new/create/edit/update/destroy/regenerate`; widened params; `mark_overridden_from_changes` on update | Modify |
| `app/components/design/views/themes/show.rb` | ＋New size + Edit entry points in `size_selector` | Modify |
| `test/controllers/design/paper_sizes_test.rb` | Integration tests for the full CRUD + regenerate | Create (rename existing edit test into it) |

**Conventions to follow (verified in-repo):**
- Components subclass `Design::Views::Base` and render inside `shell(...)`. Buttons via `render RubyUI::Button.new(variant: :primary/:outline)`. Validation errors = **plain div** (see `themes/form.rb#render_errors`).
- Integration tests: `ActionDispatch::IntegrationTest`, `sign_in :david` (admin, `can_design?`), build an **owned** theme (`user_id: users(:david).id`) so `editable_by?` is true, route helpers under `design.` namespace, `assert_select "body.design-studio"`.
- mm fields are `BigDecimal`; reuse the current `Edit#number_field`/`field_value` helpers (move them into `Form`) so values render as `"30.0"` not `"0.3e2"`.
- i18n: edit **ko.yml + en.yml only**; keep keysets identical (enforced by `test/i18n/locale_parity_test.rb`).

---

### Task 1: i18n keys (ko + en)

Add the new strings the Form/controller will reference. `edit_title` already exists; do **not** duplicate it.

**Files:**
- Modify: `config/locales/ko.yml` (under `design.paper_sizes:`)
- Modify: `config/locales/en.yml` (under `design.paper_sizes:`)
- Test: `test/i18n/locale_parity_test.rb` (existing — must stay green)

- [ ] **Step 1: Run the parity test to confirm it's green now**

Run: `bin/rails test test/i18n/locale_parity_test.rb`
Expected: PASS (baseline before edits).

- [ ] **Step 2: Add keys to `ko.yml`** under `design.paper_sizes:` (after `paper_size_styles:`)

```yaml
      page_size: "판형 크기"
      size_name: "판형 이름"
      local_name: "표시 이름"
      width: "너비 (mm)"
      height: "높이 (mm)"
      body_settings: "본문 설정"
      new_title: "새 판형"
      create_button: "판형 추가"
      update_button: "저장"
      delete: "삭제"
      delete_confirm: "이 판형을 삭제할까요?"
      regenerate: "기본값 다시 생성"
      regenerated_notice: "기본값을 다시 생성했습니다."
      created_notice: "판형을 추가했습니다."
      updated_notice: "판형을 저장했습니다."
      deleted_notice: "판형을 삭제했습니다."
```

- [ ] **Step 3: Add the same keys to `en.yml`** under `design.paper_sizes:`

```yaml
      page_size: "Page Size"
      size_name: "Size name"
      local_name: "Display name"
      width: "Width (mm)"
      height: "Height (mm)"
      body_settings: "Body Settings"
      new_title: "New Paper Size"
      create_button: "Add Paper Size"
      update_button: "Save"
      delete: "Delete"
      delete_confirm: "Delete this paper size?"
      regenerate: "Regenerate Defaults"
      regenerated_notice: "Defaults regenerated."
      created_notice: "Paper size added."
      updated_notice: "Paper size updated."
      deleted_notice: "Paper size deleted."
```

- [ ] **Step 4: Run the parity test**

Run: `bin/rails test test/i18n/locale_parity_test.rb`
Expected: PASS (identical keysets in both files).

- [ ] **Step 5: Commit**

```bash
git add config/locales/ko.yml config/locales/en.yml
git commit -m "i18n(paper_sizes): add create/edit/delete/regenerate keys"
```

---

### Task 2: Routes + `new`/`edit` rendering the new `Form`

Add the routes and the `Form` component, wire `new` and re-point `edit` at `Form`. (Regenerate's member route is added in Task 5, next to its action.)

**Files:**
- Modify: `config/routes.rb:6`
- Create: `app/components/design/views/paper_sizes/form.rb`
- Delete: `app/components/design/views/paper_sizes/edit.rb`
- Modify: `app/controllers/design/paper_sizes_controller.rb`
- Test: `test/controllers/design/paper_sizes_test.rb` (rename from `paper_sizes_edit_test.rb`)

- [ ] **Step 1: Rename the existing test file and add the `new`/`edit` render tests**

```bash
git mv test/controllers/design/paper_sizes_edit_test.rb test/controllers/design/paper_sizes_test.rb
```

Replace its class with (keep the two existing tests, add the new-form one):

```ruby
require "test_helper"

class Design::PaperSizesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david   # admin, can_design?
    @theme = Design::Theme.create!(name: "Owned #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "new renders the page-size form with identity + dimension fields" do
    get design.new_theme_paper_size_path(@theme)
    assert_response :success
    assert_select "body.design-studio"
    assert_select "input[name=?]", "paper_size[size_name]"
    assert_select "input[name=?]", "paper_size[width_mm]"
    assert_select "input[name=?]", "paper_size[height_mm]"
  end

  test "edit renders in the design layout with identity + margin fields + base styles entry" do
    get design.edit_theme_paper_size_path(@theme, @ps)
    assert_response :success
    assert_select "body.design-studio"
    assert_select "input[name=?]", "paper_size[size_name]"
    assert_select "input[name=?]", "paper_size[left_margin_mm]"
  end

  test "update persists and redirects" do
    patch design.theme_paper_size_path(@theme, @ps), params: { paper_size: { left_margin_mm: 30 } }
    assert_response :redirect
    assert_equal 30.0, @ps.reload.left_margin_mm
  end
end
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb`
Expected: FAIL — `new` route/action missing; `edit` lacks `size_name` input.

- [ ] **Step 3: Add the routes** — change `config/routes.rb:6` from `only: [:edit, :update]` to:

```ruby
    resources :paper_sizes, only: [:new, :create, :edit, :update, :destroy] do
```

(Leave the nested `base_paragraph_styles` / `document_designs` blocks untouched.)

- [ ] **Step 4: Create `Form`** at `app/components/design/views/paper_sizes/form.rb`

```ruby
module Design
  module Views
    module PaperSizes
      class Form < Design::Views::Base
        def initialize(theme:, paper_size:, base_styles: [])
          @theme = theme
          @paper_size = paper_size
          @base_styles = base_styles
        end

        def view_template
          title = @paper_size.persisted? ? @paper_size.display_name : I18n.t("design.paper_sizes.new_title")
          shell(title: title, action_slot: nil, sidebar: nil) do
            div(class: "mx-auto max-w-4xl px-6 py-10 flex flex-col gap-8") do
              render Design::Views::Breadcrumb.new(crumbs: [
                [ @theme.name, helpers.theme_path(@theme) ],
                [ title, nil ]
              ])
              h1(class: "text-2xl font-semibold text-slate-900") { title }
              render_errors
              edit_form
              base_styles_section if @paper_size.persisted? && @base_styles.any?
            end
          end
        end

        private

        def edit_form
          url    = @paper_size.persisted? ? helpers.theme_paper_size_path(@theme, @paper_size) : helpers.theme_paper_sizes_path(@theme)
          method = @paper_size.persisted? ? "patch" : "post"
          form(action: url, method: "post", class: "flex flex-col gap-6") do
            input(type: "hidden", name: "_method", value: method) if method == "patch"
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.paper_sizes.page_size") }
            div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
              text_field(I18n.t("design.paper_sizes.size_name"), :size_name, required: true)
              text_field(I18n.t("design.paper_sizes.local_name"), :local_name)
              number_field(I18n.t("design.paper_sizes.width"), :width_mm, step: "0.1")
              number_field(I18n.t("design.paper_sizes.height"), :height_mm, step: "0.1")
            end

            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.paper_sizes.margins") }
            div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
              number_field(I18n.t("design.shared.left"), :left_margin_mm, step: "0.1")
              number_field(I18n.t("design.shared.top"), :top_margin_mm, step: "0.1")
              number_field(I18n.t("design.shared.right"), :right_margin_mm, step: "0.1")
              number_field(I18n.t("design.shared.bottom"), :bottom_margin_mm, step: "0.1")
            end
            number_field(I18n.t("design.paper_sizes.binding_margin"), :binding_margin_mm, step: "0.1")

            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.paper_sizes.body_settings") }
            number_field(I18n.t("design.paper_sizes.body_line_count"), :body_line_count, step: nil)
            number_field(I18n.t("design.paper_sizes.toc_page_count"), :toc_page_count, step: nil)

            primary_label = @paper_size.persisted? ? I18n.t("design.paper_sizes.update_button") : I18n.t("design.paper_sizes.create_button")
            div(class: "flex items-center gap-3") do
              render RubyUI::Button.new(variant: :primary, type: :submit) { primary_label }
              a(href: helpers.theme_path(@theme)) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.shared.cancel") } }
            end
          end

          secondary_actions if @paper_size.persisted?
        end

        # Regenerate + Delete are separate forms (own method/confirm) so they don't nest in the main form.
        def secondary_actions
          div(class: "flex items-center gap-3 border-t border-slate-200 pt-4") do
            form(action: helpers.regenerate_theme_paper_size_path(@theme, @paper_size), method: "post", class: "inline") do
              input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
              render RubyUI::Button.new(variant: :outline, type: :submit) { I18n.t("design.paper_sizes.regenerate") }
            end
            form(action: helpers.theme_paper_size_path(@theme, @paper_size), method: "post", class: "inline",
                 data: { turbo_confirm: I18n.t("design.paper_sizes.delete_confirm") }) do
              input(type: "hidden", name: "_method", value: "delete")
              input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
              render RubyUI::Button.new(variant: :destructive, type: :submit) { I18n.t("design.paper_sizes.delete") }
            end
          end
        end

        def text_field(label_text, attr, required: false)
          div(class: "flex items-center gap-3") do
            label(class: "text-sm text-slate-600 w-40") { label_text }
            input(type: "text", name: "paper_size[#{attr}]", value: @paper_size.public_send(attr).to_s,
                  required: required, class: "border border-slate-300 rounded px-2 py-1 text-sm")
          end
        end

        def number_field(label_text, attr, step:)
          div(class: "flex items-center gap-3") do
            label(class: "text-sm text-slate-600 w-40") { label_text }
            attrs = { type: "number", name: "paper_size[#{attr}]",
                      value: field_value(@paper_size.public_send(attr)),
                      class: "border border-slate-300 rounded px-2 py-1 text-sm" }
            attrs[:step] = step if step
            input(**attrs)
          end
        end

        def field_value(value)
          case value
          when nil then nil
          when BigDecimal then value.to_s("F")
          else value.to_s
          end
        end

        # The gem has NO RubyUI::Alert — plain div (mirrors themes/form.rb).
        def render_errors
          return unless @paper_size.errors.any?
          div(class: "mb-4 rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-700") do
            ul(class: "list-disc pl-4") { @paper_size.errors.full_messages.each { |m| li { m } } }
          end
        end

        def base_styles_section
          section(class: "flex flex-col gap-3") do
            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.paper_sizes.base_text_styles") }
            div(class: "flex flex-col gap-2") { @base_styles.each { |style| base_style_row(style) } }
          end
        end

        def base_style_row(style)
          RubyUI::Card(class: "p-3 flex items-center justify-between gap-3") do
            div(class: "flex items-center gap-2 flex-wrap") do
              span(class: "font-medium text-slate-900") { style.name }
              span(class: "text-sm text-slate-500") { "(#{style.korean_name})" } if style.korean_name.present?
              span(class: "text-sm text-slate-500") { plain "— #{style.font || "inherit"}, #{style.font_size || "inherit"}pt" }
            end
            a(href: helpers.edit_theme_paper_size_base_paragraph_style_path(@theme, @paper_size, style),
              class: "text-sm font-medium text-blue-600 hover:underline") { I18n.t("design.shared.edit") }
          end
        end
      end
    end
  end
end
```

> NOTE: `variant: :destructive` is confirmed supported (`app/components/ruby_ui/button/button.rb:99` handles it; full set: `:primary, :link, :secondary, :destructive, :outline, :ghost`). Use it as written for the Delete button.

- [ ] **Step 4b: Point the controller at `Form`** — in `paper_sizes_controller.rb`, change `set_paper_size` to run only for member actions, and render `Form` from `edit`:

```ruby
    before_action :set_theme
    before_action :set_paper_size, only: [:edit, :update, :destroy, :regenerate]
    before_action :ensure_theme_editable

    def new
      @paper_size = @theme.paper_sizes.new
      render Design::Views::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size)
    end

    def edit
      @base_styles = @paper_size.paragraph_styles.order(:name)
      render Design::Views::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size, base_styles: @base_styles)
    end
```

And in `update`'s invalid branch, render `Form` instead of `Edit`:

```ruby
        render Design::Views::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size, base_styles: @paper_size.paragraph_styles.order(:name)), status: :unprocessable_entity
```

- [ ] **Step 5: Delete the old component**

```bash
git rm app/components/design/views/paper_sizes/edit.rb
```

- [ ] **Step 6: Run the tests**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb`
Expected: PASS (all three).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(paper_sizes): unify new+edit into Form, add new route"
```

---

### Task 3: `create` + `PaperSizeSeeder`

> **CORRECTION (from review):** The original plan wrongly assumed `PaperSize`'s `after_create DefaultGenerator.call` seeds document designs. It does NOT — `DefaultGenerator#call` only fills layout and iterates *existing* designs. And seeding inside `DefaultGenerator` **breaks book_design**: book_design's `ThemeGeneratorService` does `paper_sizes.create!` then loops `ALL_DOC_TYPES` calling `document_designs.create!`; an auto-seed in the shared `after_create` would collide with `DocumentDesign`'s `uniqueness: { scope: :paper_size_id }`. So seeding lives in a **dedicated gem service called only from the controller's `create`** (book_design's own generator path is untouched). The seeder mirrors book_design's `create_paper_sizes_and_designs` (`theme_generator_service.rb:201-222`) structurally, but **omits the palette-dependent cover-panel paragraph styles** (`create_cover_panel_styles` needs `resolve_attrs`/PALETTE, which the gem lacks — consistent with #1's metadata-only gem-theme decision).

**Files:**
- Create: `app/services/design/paper_size_seeder.rb`
- Modify: `app/controllers/design/paper_sizes_controller.rb`
- Test: `test/services/design/paper_size_seeder_test.rb`, `test/controllers/design/paper_sizes_test.rb`

- [ ] **Step 0: Create the `PaperSizeSeeder` service (TDD)**

Test `test/services/design/paper_size_seeder_test.rb`:

```ruby
require "test_helper"

class Design::PaperSizeSeederTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "Seed #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "seeds one document design per ALL_DOC_TYPES" do
    Design::PaperSizeSeeder.call(@ps)
    assert_equal Design::DocumentDesign::ALL_DOC_TYPES.sort, @ps.document_designs.pluck(:doc_type).sort
  end

  test "is idempotent (skips existing doc types)" do
    Design::PaperSizeSeeder.call(@ps)
    assert_no_difference -> { @ps.document_designs.count } do
      Design::PaperSizeSeeder.call(@ps)
    end
  end

  test "sets cover-panel structural attrs and zero heading height for element-less types" do
    Design::PaperSizeSeeder.call(@ps)
    front = @ps.document_designs.find_by(doc_type: "front_page")
    assert_equal "RLayout::CoverPage", front.layout_class
    assert_not front.has_header
  end
end
```

Run `bin/rails test test/services/design/paper_size_seeder_test.rb` → FAIL (no such class).

Create `app/services/design/paper_size_seeder.rb`:

```ruby
module Design
  # Seeds a paper size with one DocumentDesign per ALL_DOC_TYPES, mirroring
  # book_design's ThemeGeneratorService#create_paper_sizes_and_designs structurally
  # (heading-height + cover-panel attrs + default heading elements). It deliberately
  # does NOT create cover-panel paragraph styles — those need the host palette
  # (resolve_attrs/PALETTE), which the gem doesn't have; gem-created themes are
  # metadata-only. Idempotent: skips doc_types already present. Called from the
  # controller's `create` (NOT a model callback) so book_design's generator path
  # — which seeds its own designs after `paper_sizes.create!` — never collides.
  class PaperSizeSeeder
    def self.call(paper_size) = new(paper_size).call

    def initialize(paper_size) = @paper_size = paper_size

    def call
      existing = @paper_size.document_designs.pluck(:doc_type)
      (Design::DocumentDesign::ALL_DOC_TYPES - existing).each do |doc_type|
        attrs = { doc_type: doc_type }
        attrs[:heading_height_in_lines] = 0 unless Design::DocumentDesign.default_elements_for(doc_type).any?
        if Design::DocumentDesign::COVER_PANEL_TYPES.include?(doc_type)
          attrs[:layout_class] = "RLayout::CoverPage"
          attrs[:has_header] = false
          attrs[:has_footer] = false
        end
        dd = @paper_size.document_designs.create!(attrs)
        dd.populate_default_heading_elements
      end
      @paper_size
    end
  end
end
```

Run the seeder test → PASS. Commit: `git add -A && git commit -m "feat(paper_sizes): PaperSizeSeeder — structural doc-design seeding (no book_design collision)"`.

- [ ] **Step 0b: Ensure `DefaultGenerator` does NOT seed** — if a prior commit added a `seed_document_designs` call inside `DefaultGenerator#call`, **revert it** so `call` is back to `fill_layout` + iterate-existing only (restore the `# no-op until Task 4` comment). Seeding must live ONLY in `PaperSizeSeeder`. Run `bin/rails test` to confirm nothing else depended on it.

- [ ] **Step 1: Add failing controller tests**

```ruby
  test "create with valid params adds a size, seeds its document designs, and redirects" do
    assert_difference -> { @theme.paper_sizes.count }, 1 do
      post design.theme_paper_sizes_path(@theme),
           params: { paper_size: { size_name: "46판", width_mm: 127, height_mm: 188 } }
    end
    created = @theme.paper_sizes.order(:created_at).last
    assert_response :redirect
    assert_equal Design::DocumentDesign::ALL_DOC_TYPES.size, created.document_designs.count,
                 "create should seed every doc type via PaperSizeSeeder"
  end

  test "create with invalid params re-renders 422 with errors" do
    assert_no_difference -> { @theme.paper_sizes.count } do
      post design.theme_paper_sizes_path(@theme), params: { paper_size: { size_name: "", width_mm: 0 } }
    end
    assert_response :unprocessable_entity
    assert_select "div", text: /can.t be blank|greater than/i
  end
```

- [ ] **Step 2: Run to verify fail**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb -n "/create/"`
Expected: FAIL — no `create` action / route renders.

- [ ] **Step 3: Implement `create`**

```ruby
    def create
      @paper_size = @theme.paper_sizes.new(paper_size_params)
      if @paper_size.save
        Design::PaperSizeSeeder.call(@paper_size)
        Design::ThemeDbExportService.new(@theme).export!
        redirect_to design.edit_theme_paper_size_path(@theme, @paper_size), notice: I18n.t("design.paper_sizes.created_notice")
      else
        render Design::Views::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size), status: :unprocessable_entity
      end
    end
```

And widen `paper_size_params` to include the identity fields (full list now matches book_design):

```ruby
    def paper_size_params
      params.require(:paper_size).permit(
        :size_name, :local_name, :width_mm, :height_mm,
        :left_margin_mm, :top_margin_mm, :right_margin_mm, :bottom_margin_mm,
        :binding_margin_mm, :body_line_count, :toc_page_count
      )
    end
```

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb -n "/create/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(paper_sizes): add create with auto-generated docs"
```

---

### Task 4: Widen `update` + mark post-creation edits overridden

Without `mark_overridden_from_changes`, a field edited after creation gets silently re-derived by a later `regenerate` (overrides are otherwise only captured `before_create`).

**Files:**
- Modify: `app/controllers/design/paper_sizes_controller.rb`
- Test: `test/controllers/design/paper_sizes_test.rb`

- [ ] **Step 1: Add failing tests**

```ruby
  test "update round-trips identity + margin fields" do
    patch design.theme_paper_size_path(@theme, @ps),
          params: { paper_size: { local_name: "신국판", width_mm: 150, top_margin_mm: 22 } }
    assert_response :redirect
    @ps.reload
    assert_equal "신국판", @ps.local_name
    assert_equal 150.0, @ps.width_mm
    assert_equal 22.0, @ps.top_margin_mm
  end

  test "update marks an edited generatable field as overridden" do
    patch design.theme_paper_size_path(@theme, @ps), params: { paper_size: { body_line_count: 99 } }
    assert @ps.reload.overridden?(:body_line_count), "edited generatable field must be marked overridden"
  end

  test "update with invalid params re-renders 422" do
    patch design.theme_paper_size_path(@theme, @ps), params: { paper_size: { size_name: "" } }
    assert_response :unprocessable_entity
  end
```

- [ ] **Step 2: Run to verify the override test fails**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb -n "/update/"`
Expected: FAIL on "marks an edited generatable field as overridden".

- [ ] **Step 3: Add the `mark_overridden_from_changes` call** in `update`'s success branch (before `export!`):

```ruby
    def update
      if @paper_size.update(paper_size_params)
        @paper_size.mark_overridden_from_changes(Design::PaperSize::GENERATABLE_FIELDS)
        Design::ThemeDbExportService.new(@theme).export!
        redirect_to design.theme_path(@theme), notice: I18n.t("design.paper_sizes.updated_notice")
      else
        render Design::Views::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size, base_styles: @paper_size.paragraph_styles.order(:name)), status: :unprocessable_entity
      end
    end
```

> `updated_notice` is added to both locale files in Task 1. (The current controller uses the literal "Paper size updated." — either is fine, but use the i18n key for consistency with the other notices in this plan.)

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb -n "/update/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(paper_sizes): widen update params + mark edits overridden"
```

---

### Task 5: `regenerate`

**Files:**
- Modify: `config/routes.rb` (member route)
- Modify: `app/controllers/design/paper_sizes_controller.rb`
- Test: `test/controllers/design/paper_sizes_test.rb`

- [ ] **Step 1: Add failing test**

```ruby
  test "regenerate re-derives non-overridden defaults but preserves an overridden field" do
    # Override body_line_count via update; regenerate must keep it.
    patch design.theme_paper_size_path(@theme, @ps), params: { paper_size: { body_line_count: 99 } }
    # Clear a non-overridden margin to a sentinel so we can see it recomputed.
    @ps.update_columns(left_margin_mm: 1)
    post design.regenerate_theme_paper_size_path(@theme, @ps)
    assert_response :redirect
    @ps.reload
    assert_equal 99, @ps.body_line_count, "overridden field must survive regenerate"
    assert_not_equal 1.0, @ps.left_margin_mm, "non-overridden margin should be recomputed"
  end
```

- [ ] **Step 2: Run to verify fail**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb -n "/regenerate/"`
Expected: FAIL — no `regenerate` route/action.

- [ ] **Step 3: Add the member route** inside the `resources :paper_sizes ... do` block:

```ruby
    resources :paper_sizes, only: [:new, :create, :edit, :update, :destroy] do
      post :regenerate, on: :member
      # ... existing nested base_paragraph_styles / document_designs blocks ...
```

- [ ] **Step 4: Implement `regenerate`**

```ruby
    def regenerate
      Design::DefaultGenerator.call(@paper_size)
      Design::ThemeDbExportService.new(@theme).export!
      redirect_to design.edit_theme_paper_size_path(@theme, @paper_size), notice: I18n.t("design.paper_sizes.regenerated_notice")
    end
```

- [ ] **Step 5: Run to verify pass**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb -n "/regenerate/"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(paper_sizes): add regenerate (preserves overrides)"
```

---

### Task 6: `destroy`

book_design has **no** last/default-size guard — a plain `destroy` is the correct parity behaviour.

**Files:**
- Modify: `app/controllers/design/paper_sizes_controller.rb`
- Test: `test/controllers/design/paper_sizes_test.rb`

- [ ] **Step 1: Add failing test**

```ruby
  test "destroy removes the size and cascades its document designs" do
    other = @theme.paper_sizes.create!(size_name: "46판", width_mm: 127, height_mm: 188)
    Design::PaperSizeSeeder.call(other)   # model-built size has no docs; seed so we can assert the cascade
    dd_ids = other.document_designs.pluck(:id)
    assert dd_ids.any?
    assert_difference -> { @theme.paper_sizes.count }, -1 do
      delete design.theme_paper_size_path(@theme, other)
    end
    assert_response :redirect
    assert_equal 0, Design::DocumentDesign.where(id: dd_ids).count, "dependent: :destroy should cascade"
  end
```

- [ ] **Step 2: Run to verify fail**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb -n "/destroy/"`
Expected: FAIL — no `destroy` action.

- [ ] **Step 3: Implement `destroy`**

```ruby
    def destroy
      @paper_size.destroy
      Design::ThemeDbExportService.new(@theme).export!
      redirect_to design.theme_path(@theme), notice: I18n.t("design.paper_sizes.deleted_notice")
    end
```

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/controllers/design/paper_sizes_test.rb -n "/destroy/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(paper_sizes): add destroy (cascades document designs)"
```

---

### Task 7: Theme show entry points (＋New size + Edit)

Add a ＋New size link near the size tabs and an Edit link for the active size. Use full-page navigation (`turbo_frame: "_top"`) like the doc-card edit link, since these leave the `doc_grid` frame.

**Files:**
- Modify: `app/components/design/views/themes/show.rb` (the `size_selector` method, line 64)
- Test: `test/controllers/design/paper_sizes_test.rb` (add here — it already has the owned-theme + `@ps` setup and signs in `:david`; no need to touch the separate `themes_show_grouped_test.rb` / `themes_show_editable_chips_test.rb` files, which have their own fixtures/context)

- [ ] **Step 1: Add failing test** to `paper_sizes_test.rb`

```ruby
  test "show links to add a new paper size and edit the active one" do
    get design.theme_path(@theme, paper_size_id: @ps.id)
    assert_response :success
    assert_select "a[href=?]", design.new_theme_paper_size_path(@theme)
    assert_select "a[href=?]", design.edit_theme_paper_size_path(@theme, @ps)
  end
```

- [ ] **Step 2: Run to verify fail**

Run: `bin/rails test <that test file> -n "/new paper size/"`
Expected: FAIL — links absent.

- [ ] **Step 3: Add the links in `size_selector`** (only when editable; place beside `generate_sizes_button`):

```ruby
        def size_selector
          div(class: "flex items-center gap-2 flex-wrap") do
            @paper_sizes.each { |ps| size_pill(ps) }
            if @theme.editable_by?(Design.current_user)
              a(href: helpers.new_theme_paper_size_path(@theme), data: { turbo_frame: "_top" },
                class: "text-sm font-medium text-blue-600 hover:underline") { "＋ #{I18n.t("design.paper_sizes.new_title")}" }
              a(href: helpers.edit_theme_paper_size_path(@theme, @selected_paper_size), data: { turbo_frame: "_top" },
                class: "text-sm font-medium text-blue-600 hover:underline") { I18n.t("design.shared.edit") }
              generate_sizes_button
            end
          end
        end
```

> Read the real `size_selector` first and adapt — keep its existing wrapper classes; only add the two links. Don't regress `generate_sizes_button` or the pills.

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test <that test file> -n "/new paper size/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(themes): add new/edit paper-size entry points to show"
```

---

### Task 8: Full-suite green + push

- [ ] **Step 1: Run the whole gem suite**

Run: `bin/rails test`
Expected: PASS (0 failures, 0 errors). Pay attention to the i18n parity test and any themes-show snapshot/selector tests.

- [ ] **Step 2: Rubocop**

Run: `bundle exec rubocop app/components/design/views/paper_sizes app/controllers/design/paper_sizes_controller.rb`
Expected: no offenses (or auto-correct + re-run).

- [ ] **Step 3: Manual smoke (optional but recommended)** — in book_write or the dummy app, open a theme show, ＋New size → fill → create (lands on edit with generated docs), edit a field → save, Regenerate, Delete. Confirm the baked theme DB updates (no `Theme DB not found` errors).

- [ ] **Step 4: Push** (per the gem's normal flow — `design` pushes via SSH)

```bash
git push origin main
```

---

## Notes for the implementer

- **No migration.** Every field is an existing column on `design_paper_sizes`.
- **`ensure_theme_editable`** is a `before_action` on all actions → a non-owned/system theme returns `head :forbidden` (403). Tests use an **owned** theme so the happy path runs.
- **`ThemeDbExportService`** writes a per-theme SQLite file under the dummy app's `tmp/themes`. If the full suite is slow or you don't want disk writes, stub it the same way the themes controller tests do — but the integration tests above assume it runs for real (it's fast for a single theme).
- **RubyUI variants:** `:destructive` is supported (`button.rb:99`); the gem ships `badge, button, card, tabs` only — there is **no** `RubyUI::Alert`, so errors are plain divs.
- **DRY:** `text_field`/`number_field`/`field_value`/`base_style_row` are lifted from the deleted `Edit` — don't reinvent them.
