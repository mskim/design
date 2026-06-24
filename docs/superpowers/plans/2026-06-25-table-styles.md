# Table Styles Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port book_design's table-style editor into the `design` gem — a theme-show card grid + two-pane editor (preview / form) for `Design::TableStyle`, with Reset — surfacing the host-only preview render through a `Design.config.table_style_preview` hook.

**Architecture:** A new `Design::TableStylesController` (show/edit/update/reset) + `Design::Views::TableStyles::Edit`/`Form`, shell-wrapped, ported from book_design. The host-only preview is a config callable: `Design::TableStylePreviewsController#show` calls `Design.config.table_style_preview` and `send_data`s the JPG; components render the `<img>` only when the hook is registered, else a placeholder. `reset` uses the gem's existing `Design::ThemeStyleSeeder.reset`. Gem-only; no migration.

**Tech Stack:** Rails engine, Phlex components, RubyUI (Button), Stimulus (`design--color-field`), Minitest. `Design::TableStyle` model + `ThemeStyleSeeder` already exist.

**Spec:** `docs/superpowers/specs/2026-06-25-table-styles-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `lib/design.rb` | `Configuration#table_style_preview` accessor | Modify |
| `config/routes.rb` | `resources :table_styles` (+ preview/reset members) under themes | Modify |
| `app/controllers/design/table_style_previews_controller.rb` | Serve host-rendered preview JPG (or 404) | Create |
| `app/controllers/design/table_styles_controller.rb` | show/edit/update/reset | Create |
| `app/components/design/views/table_styles/form.rb` | Borders/Backgrounds/Cell-Text form | Create |
| `app/components/design/views/table_styles/edit.rb` | Two-pane editor (preview + form + reset) | Create |
| `app/components/design/views/themes/show.rb` | Table-styles card grid | Modify |
| `config/locales/{ko,en}.yml` | `design.table_styles.*` | Modify |
| `test/controllers/design/table_styles_test.rb` | controller + preview endpoint | Create |
| `test/controllers/design/themes_show_table_styles_test.rb` | theme-show grid | Create |

**Conventions (verified):**
- Controllers `< Design::ApplicationController` (inherits `authenticate!`, `authorize_designer!`); editors add `before_action :set_theme` + a local `set_*` + `:ensure_theme_editable` (both `set_theme`/`ensure_theme_editable` are inherited private methods). The preview controller is read-only → `set_theme` only, NO `ensure_theme_editable`.
- Explicit slate/blue/amber utilities; translate book_design's dead `text-muted-foreground`/`bg-background`/`border-input`/`bg-neutral-100`/`focus:ring-ring` tokens.
- `Design::TableStyle::BORDER_STYLES = %w[full horizontal none outer_only]`, `FONT_WEIGHTS = %w[normal bold]`. 11 editable columns.
- `design--color-field` Stimulus controller: targets `picker`/`text`, actions `pickerChanged`/`textChanged` (identical to book_design's `color-field`).
- Match book_design: explicit Save/Done/Reset, **no flash notice** on update/reset (just redirect to edit).
- Test stub for the hook: assign `Design.config.table_style_preview = ->(t, ts){ "JPG" }`, reset to `nil` in `ensure` (NO `Object#stub` — Minitest 6).
- Don't commit `Gemfile.lock`; stage files explicitly.

---

### Task 1: Config seam + routes + preview endpoint

**Files:**
- Modify: `lib/design.rb`, `config/routes.rb`
- Create: `app/controllers/design/table_style_previews_controller.rb`
- Test: `test/controllers/design/table_styles_test.rb`

- [ ] **Step 1: Write the failing preview tests**

```ruby
require "test_helper"

class Design::TableStylesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "TS #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ts = @theme.table_styles.find_by(name: "grid") # auto-seeded on theme create
  end

  test "preview sends host-rendered jpeg when the hook is registered" do
    Design.config.table_style_preview = ->(theme, table_style) { "JPGDATA" }
    get design.preview_theme_table_style_path(@theme, @ts)
    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_equal "JPGDATA", response.body
  ensure
    Design.config.table_style_preview = nil
  end

  test "preview is 404 when no hook is registered" do
    get design.preview_theme_table_style_path(@theme, @ts)
    assert_response :not_found
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/controllers/design/table_styles_test.rb`
Expected: FAIL — no `preview_theme_table_style_path` route.

- [ ] **Step 3: Add the config accessor** — in `lib/design.rb`, add `:table_style_preview` to the `Configuration` `attr_accessor` list:

```ruby
    attr_accessor :current_user, :authorize, :authenticate, :user_class, :authoring,
                  :home_url, :locale_for, :themes_dir, :table_style_preview
```

- [ ] **Step 4: Add the routes** — inside `resources :themes do … end` in `config/routes.rb` (alongside `paper_sizes`):

```ruby
    resources :table_styles, only: [ :show, :edit, :update ] do
      member do
        get :preview, to: "table_style_previews#show", as: :preview
        post :reset
      end
    end
```

- [ ] **Step 5: Create the preview controller** `app/controllers/design/table_style_previews_controller.rb`:

```ruby
module Design
  class TableStylePreviewsController < Design::ApplicationController
    before_action :set_theme

    def show
      table_style = @theme.table_styles.find(params[:id])
      blob = Design.config.table_style_preview&.call(@theme, table_style)
      return head :not_found unless blob

      expires_now
      send_data blob, type: "image/jpeg", disposition: "inline"
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
  end
end
```

- [ ] **Step 6: Run to verify it passes**

Run: `bin/rails test test/controllers/design/table_styles_test.rb`
Expected: PASS (both preview tests).

- [ ] **Step 7: Commit**

```bash
git add lib/design.rb config/routes.rb app/controllers/design/table_style_previews_controller.rb test/controllers/design/table_styles_test.rb
git commit -m "feat(table_styles): config preview hook + preview endpoint + routes"
```

---

### Task 2: `TableStylesController` + `Form` + `Edit`

**Files:**
- Create: `app/controllers/design/table_styles_controller.rb`
- Create: `app/components/design/views/table_styles/form.rb`
- Create: `app/components/design/views/table_styles/edit.rb`
- Modify: `config/locales/{ko,en}.yml`
- Test: `test/controllers/design/table_styles_test.rb`

- [ ] **Step 1: Add the failing controller/component tests**

```ruby
  test "edit renders the two-pane editor with the three sections + reset" do
    get design.edit_theme_table_style_path(@theme, @ts)
    assert_response :success
    assert_select "body.design-studio"
    assert_select "input[name=?]", "table_style[border_width]"
    assert_select "select[name=?]", "table_style[border_style]"
    assert_select "input[name=?]", "table_style[header_background]"
    assert_select "form[action=?]", design.reset_theme_table_style_path(@theme, @ts)
  end

  test "edit shows a no-preview placeholder when no hook is registered" do
    get design.edit_theme_table_style_path(@theme, @ts)
    assert_select "turbo-frame#preview_frame", count: 0   # placeholder renders no preview frame
    assert_includes response.body, I18n.t("design.table_styles.no_preview")
  end

  test "edit shows the preview img when the hook is registered" do
    Design.config.table_style_preview = ->(t, ts) { "JPG" }
    get design.edit_theme_table_style_path(@theme, @ts)
    assert_select "turbo-frame#preview_frame img[src*=?]", "preview"
  ensure
    Design.config.table_style_preview = nil
  end

  test "update round-trips fields and redirects to edit" do
    patch design.theme_table_style_path(@theme, @ts),
          params: { table_style: { border_width: 3.5, header_font_weight: "bold", header_background: "#222222" } }
    assert_redirected_to design.edit_theme_table_style_path(@theme, @ts)
    @ts.reload
    assert_equal 3.5, @ts.border_width
    assert_equal "bold", @ts.header_font_weight
    assert_equal "#222222", @ts.header_background
  end

  test "update with invalid params re-renders 422" do
    patch design.theme_table_style_path(@theme, @ts), params: { table_style: { border_style: "bogus" } }
    assert_response :unprocessable_entity
  end

  test "reset restores the seeded defaults" do
    original = @ts.border_width
    @ts.update_columns(border_width: 99)
    post design.reset_theme_table_style_path(@theme, @ts)
    assert_redirected_to design.edit_theme_table_style_path(@theme, @ts)
    assert_equal original, @ts.reload.border_width
  end

  test "show redirects to edit" do
    get design.theme_table_style_path(@theme, @ts)
    assert_redirected_to design.edit_theme_table_style_path(@theme, @ts)
  end

  test "a non-editable (system) theme is forbidden" do
    sys = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sys_ts = sys.table_styles.find_by(name: "grid")
    get design.edit_theme_table_style_path(sys, sys_ts)
    assert_response :forbidden
  end
```
> NOTE: `border_style: "bogus"` must fail validation (the model validates inclusion in `BORDER_STYLES` `allow_nil: true` — "bogus" is non-nil and invalid → 422). The reset test asserts the value returns to the seeded default WITHOUT hardcoding it.

- [ ] **Step 2: Run to verify fail**

Run: `bin/rails test test/controllers/design/table_styles_test.rb`
Expected: FAIL — no `TableStylesController` / components.

- [ ] **Step 3: Create the controller** `app/controllers/design/table_styles_controller.rb`:

```ruby
module Design
  class TableStylesController < Design::ApplicationController
    before_action :set_theme
    before_action :set_table_style
    before_action :ensure_theme_editable

    def show
      redirect_to design.edit_theme_table_style_path(@theme, @table_style)
    end

    def edit
      render Design::Views::TableStyles::Edit.new(theme: @theme, table_style: @table_style)
    end

    def update
      if @table_style.update(table_style_params)
        redirect_to design.edit_theme_table_style_path(@theme, @table_style)
      else
        render Design::Views::TableStyles::Edit.new(theme: @theme, table_style: @table_style), status: :unprocessable_entity
      end
    end

    def reset
      Design::ThemeStyleSeeder.reset(@theme, @table_style.name)
      redirect_to design.edit_theme_table_style_path(@theme, @table_style)
    end

    private

    def set_table_style
      @table_style = @theme.table_styles.find(params[:id])
    end

    def table_style_params
      params.require(:table_style).permit(
        :border_width, :border_color, :border_style,
        :header_background, :alternate_row_background,
        :header_text_color, :body_text_color,
        :cell_padding, :outer_border_width, :header_separator_width,
        :header_font_weight
      )
    end
  end
end
```

- [ ] **Step 4: Create the Form component** `app/components/design/views/table_styles/form.rb`:

```ruby
module Design
  module Views
    module TableStyles
      class Form < Design::Views::Base
        def initialize(theme:, table_style:)
          @theme = theme
          @style = table_style
        end

        def view_template
          form(action: helpers.theme_table_style_path(@theme, @style), method: "post", class: "flex-1 flex flex-col") do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: "hidden", name: "_method", value: "patch")
            render_errors
            div(class: "flex-1 px-4 py-3 flex flex-col gap-4") do
              section(I18n.t("design.table_styles.borders")) do
                row do
                  field(I18n.t("design.table_styles.width"), :border_width, type: "number", step: "0.1")
                  select_field(I18n.t("design.table_styles.style"), :border_style, Design::TableStyle::BORDER_STYLES)
                end
                color_field(I18n.t("design.table_styles.color"), :border_color)
                row do
                  field(I18n.t("design.table_styles.outer_width"), :outer_border_width, type: "number", step: "0.1")
                  field(I18n.t("design.table_styles.header_sep"), :header_separator_width, type: "number", step: "0.1")
                end
              end
              section(I18n.t("design.table_styles.backgrounds")) do
                color_field(I18n.t("design.table_styles.header_bg"), :header_background)
                color_field(I18n.t("design.table_styles.alt_row_bg"), :alternate_row_background)
              end
              section(I18n.t("design.table_styles.cell_text")) do
                row do
                  color_field(I18n.t("design.table_styles.header_color"), :header_text_color)
                  color_field(I18n.t("design.table_styles.body_color"), :body_text_color)
                end
                row do
                  select_field(I18n.t("design.table_styles.header_weight"), :header_font_weight, Design::TableStyle::FONT_WEIGHTS)
                  field(I18n.t("design.table_styles.cell_padding"), :cell_padding, type: "number", step: "0.5")
                end
              end
            end
            div(class: "border-t border-slate-200 px-4 py-3 flex items-center justify-end gap-2") do
              render RubyUI::Button.new(variant: :primary, type: :submit) { I18n.t("design.shared.save") }
              a(href: helpers.theme_path(@theme)) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.table_styles.done") } }
            end
          end
        end

        private

        def section(title, &block)
          div(class: "flex flex-col gap-2") do
            h3(class: "text-xs font-semibold uppercase tracking-wider text-slate-500") { title }
            div(class: "flex flex-col gap-2", &block)
          end
        end

        def row(&block) = div(class: "grid grid-cols-2 gap-3", &block)

        def field(label_text, attr, type: "text", **opts)
          div do
            label(class: "block text-xs text-slate-500 mb-0.5") { label_text }
            input(type: type, name: "table_style[#{attr}]", value: @style.public_send(attr).to_s,
                  class: "w-full rounded-md border border-slate-300 px-2.5 py-1 text-sm", **opts)
          end
        end

        def color_field(label_text, attr)
          div(data: { controller: "design--color-field" }) do
            label(class: "block text-xs text-slate-500 mb-0.5") { label_text }
            div(class: "flex gap-1.5 items-center") do
              input(type: "color", value: normalize_color(@style.public_send(attr)),
                    class: "w-7 h-7 rounded border border-slate-300 cursor-pointer shrink-0 p-0",
                    data: { "design--color-field-target": "picker", action: "input->design--color-field#pickerChanged" })
              input(type: "text", name: "table_style[#{attr}]", value: @style.public_send(attr).to_s, placeholder: "#rrggbb",
                    class: "flex-1 min-w-0 rounded-md border border-slate-300 px-2 py-1 text-sm",
                    data: { "design--color-field-target": "text", action: "input->design--color-field#textChanged" })
            end
          end
        end

        def select_field(label_text, attr, options)
          current = @style.public_send(attr).to_s
          div do
            label(class: "block text-xs text-slate-500 mb-0.5") { label_text }
            select(name: "table_style[#{attr}]", class: "w-full rounded-md border border-slate-300 px-2.5 py-1 text-sm") do
              options.each { |opt| option(value: opt, selected: current == opt) { opt } }
            end
          end
        end

        def normalize_color(color)
          return "#ffffff" if color.nil? || color.to_s.strip.empty?
          color.to_s.start_with?("#") ? color : "#ffffff"
        end

        def render_errors
          return unless @style.errors.any?
          div(class: "rounded-md border border-red-300 bg-red-50 p-3 mb-2 mx-4 mt-2") do
            ul(class: "list-disc pl-4 text-sm text-red-700") { @style.errors.full_messages.each { |m| li { m } } }
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Create the Edit component** `app/components/design/views/table_styles/edit.rb`:

```ruby
module Design
  module Views
    module TableStyles
      class Edit < Design::Views::Base
        def initialize(theme:, table_style:)
          @theme = theme
          @table_style = table_style
        end

        def view_template
          shell(title: "#{@table_style.name.capitalize} #{I18n.t("design.table_styles.edit_suffix")}", action_slot: nil, sidebar: nil) do
            div(class: "flex flex-col lg:flex-row gap-6 px-6 py-8") do
              preview_pane
              form_pane
            end
          end
        end

        private

        def preview_pane
          div(class: "flex-1 min-w-0 flex items-start justify-center rounded-lg border border-slate-200 bg-slate-50 p-4") do
            if Design.config.table_style_preview
              turbo_frame_tag("preview_frame") do
                img(src: helpers.preview_theme_table_style_path(@theme, @table_style, t: @table_style.updated_at.to_i),
                    alt: @table_style.name, class: "max-w-full border border-slate-200 bg-white shadow-sm")
              end
            else
              div(class: "py-16 text-sm text-slate-400") { I18n.t("design.table_styles.no_preview") }
            end
          end
        end

        def form_pane
          div(class: "lg:w-96 lg:shrink-0 flex flex-col rounded-lg border border-slate-200 bg-white") do
            render Design::Views::TableStyles::Form.new(theme: @theme, table_style: @table_style)
            reset_form
          end
        end

        def reset_form
          div(class: "border-t border-slate-200 px-4 py-3") do
            form(action: helpers.reset_theme_table_style_path(@theme, @table_style), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
              button(type: "submit",
                     class: "px-3 py-1.5 rounded-md text-xs font-medium border border-amber-300 text-amber-700 hover:bg-amber-50",
                     data: { turbo_confirm: I18n.t("design.table_styles.reset_confirm") }) { I18n.t("design.table_styles.reset") }
            end
          end
        end
      end
    end
  end
end
```
> `turbo_frame_tag` comes from `Phlex::Rails::Helpers::TurboFrameTag` (included in `Base`). `Design.config.table_style_preview` (a Proc) is truthy when set.

- [ ] **Step 6: Add i18n** under a new `design.table_styles:` block in BOTH ko.yml + en.yml (identical keysets). Keys + values:
  - `section_title` "표 스타일" / "Table Styles"
  - `edit_suffix` "표 스타일" / "Table Style"
  - `borders` "테두리" / "Borders"; `backgrounds` "배경" / "Backgrounds"; `cell_text` "셀 텍스트" / "Cell Text"
  - `width` "두께" / "Width"; `style` "스타일" / "Style"; `color` "색상" / "Color"; `outer_width` "바깥 두께" / "Outer Width"; `header_sep` "헤더 구분선" / "Header Sep."
  - `header_bg` "헤더 배경" / "Header BG"; `alt_row_bg` "교대 행 배경" / "Alt Row BG"
  - `header_color` "헤더 색상" / "Header Color"; `body_color` "본문 색상" / "Body Color"; `header_weight` "헤더 굵기" / "Header Weight"; `cell_padding` "셀 여백" / "Cell Padding"
  - `done` "완료" / "Done"; `reset` "기본값으로 초기화" / "Reset to defaults"; `reset_confirm` "이 표 스타일을 기본값으로 초기화할까요?" / "Reset this table style to defaults?"
  - `no_preview` "미리보기 없음" / "No preview"; `card_subtitle` "테두리, 색상, 여백" / "Borders, colors, padding"
  (Reuse `design.shared.save`.)

- [ ] **Step 7: Run the tests**

Run: `bin/rails test test/controllers/design/table_styles_test.rb`
Expected: PASS (all). Then the i18n parity test: `bin/rails test test/i18n/locale_parity_test.rb` → PASS.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/design/table_styles_controller.rb app/components/design/views/table_styles/form.rb app/components/design/views/table_styles/edit.rb config/locales/ko.yml config/locales/en.yml test/controllers/design/table_styles_test.rb
git commit -m "feat(table_styles): editor controller + two-pane Edit/Form"
```

---

### Task 3: Theme-show table-styles grid

**Files:**
- Modify: `app/components/design/views/themes/show.rb`
- Test: `test/controllers/design/themes_show_table_styles_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Design::ThemesShowTableStylesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "TSG #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ts = @theme.table_styles.find_by(name: "grid")
  end

  test "theme show lists table styles linking to their editors" do
    get design.theme_path(@theme)
    assert_response :success
    assert_includes response.body, I18n.t("design.table_styles.section_title")
    assert_select "a[href=?]", design.edit_theme_table_style_path(@theme, @ts)
  end
end
```

- [ ] **Step 2: Run to verify fail** → FAIL (no grid).

- [ ] **Step 3: Add the section** — in `app/components/design/views/themes/show.rb`, call `table_styles_section` in `view_template` (after the `if @selected_paper_size … end` block, still inside the container `div`; table styles are theme-level and shown regardless of selected size), and add the private methods:

```ruby
        def table_styles_section
          styles = @theme.table_styles.order(:name)
          return if styles.empty?
          div(class: "flex flex-col gap-3") do
            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.table_styles.section_title") }
            div(class: "grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3") do
              styles.each { |ts| table_style_card(ts) }
            end
          end
        end

        def table_style_card(ts)
          a(href: helpers.edit_theme_table_style_path(@theme, ts),
            class: "block rounded-lg border border-slate-200 overflow-hidden hover:shadow-md hover:border-blue-300 transition-all bg-white") do
            div(class: "aspect-[4/3] bg-slate-50 flex items-center justify-center overflow-hidden") do
              if Design.config.table_style_preview
                img(src: helpers.preview_theme_table_style_path(@theme, ts, t: ts.updated_at.to_i), alt: ts.name, class: "w-full h-full object-contain")
              else
                span(class: "text-xs text-slate-400") { I18n.t("design.table_styles.no_preview") }
              end
            end
            div(class: "px-3 py-2 border-t border-slate-200") do
              h3(class: "text-sm font-medium text-slate-900") { ts.name.capitalize }
              p(class: "text-xs text-slate-500") { I18n.t("design.table_styles.card_subtitle") }
            end
          end
        end
```
> Read `view_template` first; add the `table_styles_section` call at the right spot inside the container div without disturbing the existing `header_section`/`size_selector`/`doc_grid` flow.

- [ ] **Step 4: Run** the test → PASS. Also re-run the themes-show suite to be safe: `bin/rails test test/controllers/design/themes_show_grouped_test.rb test/controllers/design/themes_show_editable_chips_test.rb`.

- [ ] **Step 5: Commit**

```bash
git add app/components/design/views/themes/show.rb test/controllers/design/themes_show_table_styles_test.rb
git commit -m "feat(themes): table-styles grid on theme show"
```

---

### Task 4: Full suite + freshness + rubocop + push

- [ ] **Step 1: Full suite** — `bin/rails test` → 0 failures/errors. Watch i18n parity + themes-show + the new table-styles tests.

- [ ] **Step 2: Tailwind freshness** — the editor/grid add utilities (amber border, `aspect-[4/3]`, etc.). If `test/design_tailwind_build_freshness_test.rb` fails, rebuild + commit `app/assets/builds/design.css`:

```bash
bin/rails runner 'require Design::Engine.root.join("lib/design/tailwind_scoper"); require "tailwindcss/ruby"; require "tmpdir"; \
  exe = Tailwindcss::Ruby.executable.to_s; root = Design::Engine.root; \
  Dir.mktmpdir { |d| raw = File.join(d,"raw.css"); system(exe, "-i", root.join("app/assets/tailwind/design.css").to_s, "-o", raw, "--minify", exception: true); \
  File.write(root.join("app/assets/builds/design.css"), Design::TailwindScoper.scope(File.read(raw), under: ".design-studio")) }'
bin/rails test test/design_tailwind_build_freshness_test.rb
git add app/assets/builds/design.css && git commit -m "chore(design): rebuild design.css for table-styles utilities"
```

- [ ] **Step 3: Rubocop** (omakase config):

```bash
bundle exec rubocop --config "$(bundle show rubocop-rails-omakase)/rubocop.yml" \
  app/controllers/design/table_styles_controller.rb \
  app/controllers/design/table_style_previews_controller.rb \
  app/components/design/views/table_styles/form.rb \
  app/components/design/views/table_styles/edit.rb
```
Expected: clean, or offenses consistent with surrounding style.

- [ ] **Step 4: Manual smoke (optional)** — open a theme show → table-styles grid (placeholders, no hook registered) → click a card → editor opens (two-pane, preview placeholder + form) → edit a field → Save (redirects, value persists) → Reset (turbo-confirm → defaults restored).

- [ ] **Step 5: Push** — `git push origin main`.

---

## Notes for the implementer

- **No migration, no model change.** `Design::TableStyle` + `ThemeStyleSeeder.reset` already exist.
- **Preview is placeholder in #5** — no host registers `Design.config.table_style_preview` yet, so the editor + grid show "No preview" everywhere; the `<img>`/`turbo-frame` only render when a host registers a renderer (book_design in #6). Editing is fully functional regardless.
- **Match book_design:** no flash notice on update/reset (redirect to edit is the feedback). Reset is destructive → keep the `turbo_confirm`.
- **`design--color-field`** is byte-identical to book_design's `color-field` (including `pickerChanged` → `hexToCmyk`): swap the controller name + the `*-target`/`action` data keys, nothing else. Picker-drag submits a `CMYK=c,m,y,k` string (the text field also accepts `#hex`/named); seeded defaults are `#hex`. This is the established book_design behavior — the host renderer (registered in #6) handles both, like the rest of the gem's color pipeline. Not a bug; do not add a hex-only mode.
- **Auth:** edit/update/reset go through `ensure_theme_editable` (system/non-owned theme → 403). The preview endpoint is read-only (designer auth only, no editable check) — matches book_design.
- The `@theme.table_styles.find_by(name: "grid")` in tests relies on the `Theme.after_create` auto-seed (all 5 presets) — confirmed by the existing `table_style_test.rb` which `destroy_all`s them; here we KEEP them to have a real style to edit.
