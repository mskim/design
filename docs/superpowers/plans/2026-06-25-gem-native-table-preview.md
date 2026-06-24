# Gem-Native Table-Style Preview Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move table-style preview rendering into the `design` gem so every host (book_design, book_write, the Docker server) gets real table previews with zero registration; `Design.config.table_style_preview` becomes an optional override.

**Architecture:** Port book_design's 5-service render pipeline (`TableStyleResolver` → `SingleTablePdf` → Vips) into the gem under `Design::`, DRY the shared PDF→JPG step into `Design::PdfToJpg`, and have `Design::TableStylePreviewsController#show` render natively (hook = override). Then delete book_design's now-redundant copy.

**Tech Stack:** Rails engine (`design` gem), Phlex components, `doc_processor_rb` (`InlineTable`), HexaPDF, ruby-vips, Minitest.

**Spec:** `/Users/mskim/Development/ruby/gems/design/docs/superpowers/specs/2026-06-25-gem-native-table-preview-design.md`

---

## Conventions for the implementer

- **Two repos.** Tasks 1–7 are in the **gem** (`/Users/mskim/Development/ruby/gems/design`). Task 8 is in **book_design** (`/Users/mskim/Development/book/book_design`). `cd` into the right repo per task.
- **Run gem tests** from the gem root: `bin/rails test <path>` (the gem's `bin/rails` boots `test/dummy`). Whole gem suite: `bin/rails test`.
- **Run book_design tests** from its root: `bin/rails test <path>`. ⚠️ **NEVER** run `db:reset` / `db:setup` / `bin/setup` in book_design — only `bin/rails test` (the dev DB was wiped once by a careless reset). Do not touch the dev database.
- **Test infra already restores `Design.config`.** The gem's `test/test_helper.rb` snapshots `Design.config.dup` in `setup` and restores it in `teardown` (around every test, parallel-safe). So a test that sets `Design.config.table_style_preview = …` needs **no** manual `ensure` — the teardown handles it.
- **Minitest 6 has no mock** (no `stub`, no Mocha). Stub via the config hook (restored by teardown) or `define_singleton_method`. Prefer the hook path for the controller error test.
- **Namespacing.** All new gem services live in `app/services/design/` under `module Design`. Tests in `test/services/design/`.
- **Route helpers in gem tests** are engine-namespaced: `design.preview_theme_table_style_path(theme, ts)`, `design.theme_path(theme)`, etc. `sign_in :david` (fixture) authenticates.
- **Commit after each task** (the `git add` lists name exact paths — do not `git add -A`). Conventional Commits.

## File Structure (gem unless noted)

| File | Responsibility |
|---|---|
| `app/services/design/hex_to_cmyk.rb` (new) | `Design::HexToCmyk` — hex → CMYK array |
| `app/services/design/table_style_resolver.rb` (new) | `Design::TableStyleResolver` — `TableStyle` + theme cell styles → `style_hash` |
| `app/services/design/pdf_to_jpg.rb` (new) | `Design::PdfToJpg.convert(pdf, jpg, dpi:)` — shared Vips step |
| `app/services/design/single_table_pdf.rb` (new) | `Design::SingleTablePdf` — 1-page table PDF via `InlineTable` |
| `app/services/design/table_style_preview_sample.rb` (new) | `Design::TableStylePreviewSample::SAMPLE` — sample rows |
| `app/services/design/table_style_preview_service.rb` (new) | `Design::TableStylePreviewService.call(theme, ts)` — orchestrator → JPG blob |
| `app/services/design/preview_service.rb` (modify) | `convert_pdf_to_jpg` delegates to `Design::PdfToJpg` |
| `app/controllers/design/table_style_previews_controller.rb` (modify) | gem-native default; hook override; rescue → 422 |
| `app/components/design/views/table_styles/edit.rb` (modify) | always render preview `<img>` |
| `app/components/design/views/themes/show.rb` (modify) | always render table-style card `<img>` |
| `config/locales/en.yml`, `config/locales/ko.yml` (modify) | remove `table_styles.no_preview` |
| `design.gemspec` (modify) | add `hexapdf` dependency |
| **book_design** delete: `app/services/{table_style_preview_renderer,table_style_resolver,single_table_pdf,table_style_preview_sample,hex_to_cmyk}.rb`, `test/services/{table_style_resolver,hex_to_cmyk}_test.rb` | retire the host copy |
| **book_design** `config/initializers/design.rb` (modify) | drop the `c.table_style_preview` line |
| **book_design** `test/integration/studio_cutover_test.rb` (modify) | drop hook setup; assert gem-native preview |

---

### Task 1: `Design::HexToCmyk`

**Files:**
- Create: `app/services/design/hex_to_cmyk.rb`
- Test: `test/services/design/hex_to_cmyk_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/design/hex_to_cmyk_test.rb
require "test_helper"

class Design::HexToCmykTest < ActiveSupport::TestCase
  test "white is all zero" do
    assert_equal [ 0, 0, 0, 0 ], Design::HexToCmyk.call("#ffffff")
  end

  test "black is full key" do
    assert_equal [ 0, 0, 0, 100 ], Design::HexToCmyk.call("#000000")
  end

  test "grey is key only" do
    assert_equal [ 0, 0, 0, 20 ], Design::HexToCmyk.call("#cccccc")
  end

  test "nil and blank return nil" do
    assert_nil Design::HexToCmyk.call(nil)
    assert_nil Design::HexToCmyk.call("")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/design/hex_to_cmyk_test.rb`
Expected: FAIL — `NameError: uninitialized constant Design::HexToCmyk`

- [ ] **Step 3: Write the implementation** (faithful port, namespaced)

```ruby
# app/services/design/hex_to_cmyk.rb
module Design
  class HexToCmyk
    def self.call(hex)
      return nil if hex.nil? || hex == ""
      h = hex.delete_prefix("#")
      r = h[0, 2].to_i(16) / 255.0
      g = h[2, 2].to_i(16) / 255.0
      b = h[4, 2].to_i(16) / 255.0
      k = 1 - [ r, g, b ].max
      if k >= 1.0
        [ 0, 0, 0, 100 ]
      else
        c = ((1 - r - k) / (1 - k) * 100).round
        m = ((1 - g - k) / (1 - k) * 100).round
        y = ((1 - b - k) / (1 - k) * 100).round
        [ c, m, y, (k * 100).round ]
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/design/hex_to_cmyk_test.rb`
Expected: PASS (4 runs, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/services/design/hex_to_cmyk.rb test/services/design/hex_to_cmyk_test.rb
git commit -m "feat(table-preview): add Design::HexToCmyk"
```

---

### Task 2: `Design::TableStyleResolver`

Resolves a `Design::TableStyle` + the theme's `table_heading_cell`/`table_body_cell` base paragraph styles into the `style_hash` `InlineTable` consumes. Depends on Task 1.

**Files:**
- Create: `app/services/design/table_style_resolver.rb`
- Test: `test/services/design/table_style_resolver_test.rb`

- [ ] **Step 1: Write the failing test**

`Design::Theme.create!` triggers `after_create` → `ThemeStyleSeeder`, which seeds the 5 table styles (`grid`, etc.) **and** the `table_heading_cell` / `table_body_cell` base paragraph styles. So a freshly-created theme is fully resolvable.

```ruby
# test/services/design/table_style_resolver_test.rb
require "test_helper"

class Design::TableStyleResolverTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "TSR #{SecureRandom.hex(3)}", locale: "ko")
    @ts = @theme.table_styles.find_by(name: "grid")
  end

  test "resolves a style hash with CMYK colors and required keys" do
    hash = Design::TableStyleResolver.call(@theme, @ts)

    assert_equal @ts.name, hash[:name]
    assert_kind_of Float, hash[:border_width]
    assert_equal :full, hash[:border_style] if @ts.border_style.nil?
    # colors are converted to CMYK arrays (or nil when the source color is blank)
    [ :border_color, :header_background, :header_text_color,
      :alternate_row_background, :body_text_color ].each do |key|
      val = hash[key]
      assert(val.nil? || (val.is_a?(Array) && val.size == 4), "#{key} not a CMYK array: #{val.inspect}")
    end
    assert_nil hash[:body_background]
  end

  test "includes header and body cell paragraph hashes from the theme" do
    hash = Design::TableStyleResolver.call(@theme, @ts)
    assert hash.key?(:header_cell_paragraph_style)
    assert hash.key?(:body_cell_paragraph_style)
    # seeded theme has the cell paragraph styles, so these resolve to hashes
    assert_kind_of Hash, hash[:header_cell_paragraph_style]
    assert hash[:header_cell_paragraph_style].key?(:font_size)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/design/table_style_resolver_test.rb`
Expected: FAIL — `NameError: uninitialized constant Design::TableStyleResolver`

- [ ] **Step 3: Write the implementation** (port; `HexToCmyk` → `Design::HexToCmyk`)

```ruby
# app/services/design/table_style_resolver.rb
module Design
  class TableStyleResolver
    def self.call(theme, table_style)
      new(theme, table_style).call
    end

    def initialize(theme, table_style)
      @theme = theme
      @table_style = table_style
    end

    def call
      {
        name: @table_style.name,
        border_width: @table_style.border_width.to_f,
        border_color: Design::HexToCmyk.call(@table_style.border_color),
        border_style: (@table_style.border_style || "full").to_sym,
        header_background: Design::HexToCmyk.call(@table_style.header_background),
        header_font_weight: (@table_style.header_font_weight || "bold").to_sym,
        header_text_color: Design::HexToCmyk.call(@table_style.header_text_color),
        body_background: nil,
        alternate_row_background: Design::HexToCmyk.call(@table_style.alternate_row_background),
        body_text_color: Design::HexToCmyk.call(@table_style.body_text_color),
        cell_padding: @table_style.cell_padding.to_f,
        outer_border_width: @table_style.outer_border_width.to_f,
        header_separator_width: @table_style.header_separator_width&.to_f,
        header_cell_paragraph_style: paragraph_hash("table_heading_cell"),
        body_cell_paragraph_style:   paragraph_hash("table_body_cell")
      }
    end

    private

    def paragraph_hash(name)
      ps = @theme.base_paragraph_styles.find_by(name: name)
      return nil unless ps
      {
        font: ps.font,
        font_size: ps.font_size&.to_f,
        text_align: ps.text_align,
        vertical_align: ps.vertical_align,
        text_color: ps.text_color,
        padding_top: ps.space_before&.to_f,
        padding_bottom: ps.space_after&.to_f
      }
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/design/table_style_resolver_test.rb`
Expected: PASS (2 runs, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/services/design/table_style_resolver.rb test/services/design/table_style_resolver_test.rb
git commit -m "feat(table-preview): add Design::TableStyleResolver"
```

---

### Task 3: `Design::PdfToJpg` (extract the shared Vips step)

Extract the byte-identical PDF→JPG conversion out of `PreviewService` so both it and the new table renderer share one implementation. `PreviewService`'s behavior must not change — its tests must stay green.

**Files:**
- Create: `app/services/design/pdf_to_jpg.rb`
- Modify: `app/services/design/preview_service.rb` (the `convert_pdf_to_jpg` private method)
- Test: `test/services/design/pdf_to_jpg_test.rb`

- [ ] **Step 1: Write the failing test** (round-trips a HexaPDF one-pager → non-empty JPEG)

```ruby
# test/services/design/pdf_to_jpg_test.rb
require "test_helper"
require "hexapdf"
require "tempfile"

class Design::PdfToJpgTest < ActiveSupport::TestCase
  test "converts a PDF file into a non-empty JPEG file" do
    pdf = Tempfile.new(%w[p2j .pdf])
    jpg = Tempfile.new(%w[p2j .jpg])
    begin
      doc = HexaPDF::Document.new
      doc.pages.add([ 0, 0, 200, 100 ]).canvas.tap { |c| c.rectangle(10, 10, 50, 50).fill }
      doc.write(pdf.path)

      out = Design::PdfToJpg.convert(pdf.path, jpg.path, dpi: 72)

      assert_equal jpg.path, out
      assert File.exist?(jpg.path)
      assert File.size(jpg.path) > 500, "jpeg looks empty"
    ensure
      pdf.close!
      jpg.close!
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/design/pdf_to_jpg_test.rb`
Expected: FAIL — `NameError: uninitialized constant Design::PdfToJpg`

- [ ] **Step 3: Write `Design::PdfToJpg`**

```ruby
# app/services/design/pdf_to_jpg.rb
module Design
  # Shared PDF→JPG rendering (ruby-vips). Reads the PDF as a buffer to bypass
  # Vips file-path caching, flattens any alpha to white, JPEG-encodes at Q 85.
  class PdfToJpg
    def self.convert(pdf_path, jpg_path, dpi: 150)
      pdf_data = File.binread(pdf_path)
      image = Vips::Image.new_from_buffer(pdf_data, "", dpi: dpi, access: :sequential)
      image = image.flatten(background: [ 255, 255, 255 ]) if image.bands == 4
      image.jpegsave(jpg_path, Q: 85)
      jpg_path
    end
  end
end
```

- [ ] **Step 4: Refactor `PreviewService#convert_pdf_to_jpg` to delegate**

Replace the method body (keep the `PREVIEW_DPI = 150` constant where it is):

```ruby
    def convert_pdf_to_jpg(pdf_path, jpg_path)
      Design::PdfToJpg.convert(pdf_path, jpg_path, dpi: PREVIEW_DPI)
    end
```

- [ ] **Step 5: Run the new test AND the existing PreviewService tests (no regression)**

Run: `bin/rails test test/services/design/pdf_to_jpg_test.rb test/services/design/preview_service_test.rb test/services/design/preview_service_master_page_test.rb`
Expected: PASS — all green (the PreviewService refactor is behavior-preserving)

- [ ] **Step 6: Commit**

```bash
git add app/services/design/pdf_to_jpg.rb app/services/design/preview_service.rb test/services/design/pdf_to_jpg_test.rb
git commit -m "refactor(preview): extract shared Design::PdfToJpg from PreviewService"
```

---

### Task 4: `Design::SingleTablePdf` + `Design::TableStylePreviewSample` + gemspec dependency

The 1-page table-PDF writer (via `DocProcessorRb::Layout::InlineTable`) and its sample data. `SingleTablePdf` adds a first-party `require "hexapdf"`, so declare `hexapdf` in the gemspec.

**Files:**
- Create: `app/services/design/single_table_pdf.rb`
- Create: `app/services/design/table_style_preview_sample.rb`
- Modify: `design.gemspec`
- Test: `test/services/design/single_table_pdf_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/design/single_table_pdf_test.rb
require "test_helper"
require "tempfile"

class Design::SingleTablePdfTest < ActiveSupport::TestCase
  test "writes a non-empty single-page table PDF from the sample rows" do
    theme = Design::Theme.create!(name: "STP #{SecureRandom.hex(3)}", locale: "ko")
    style_hash = Design::TableStyleResolver.call(theme, theme.table_styles.find_by(name: "grid"))
    pdf = Tempfile.new(%w[stp .pdf])
    begin
      out = Design::SingleTablePdf.write(pdf.path,
        rows: Design::TableStylePreviewSample::SAMPLE[:rows], style_hash: style_hash)
      assert_equal pdf.path, out
      assert File.size(pdf.path) > 500, "pdf looks empty"
      assert_equal "%PDF", File.binread(pdf.path, 4)
    ensure
      pdf.close!
    end
  end

  test "the sample has one header row and three body rows" do
    rows = Design::TableStylePreviewSample::SAMPLE[:rows]
    assert_equal 1, rows.count { |r| r[:kind] == :header }
    assert_equal 3, rows.count { |r| r[:kind] == :body }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/design/single_table_pdf_test.rb`
Expected: FAIL — `NameError: uninitialized constant Design::TableStylePreviewSample` (or `Design::SingleTablePdf`)

- [ ] **Step 3: Write `Design::TableStylePreviewSample`** (port, namespaced)

```ruby
# app/services/design/table_style_preview_sample.rb
module Design
  class TableStylePreviewSample
    SAMPLE = {
      rows: [
        { kind: :header, cells: [ { text: "Region" }, { text: "Population" }, { text: "Area (km²)" } ] },
        { kind: :body,   cells: [ { text: "Seoul" }, { text: "9.7M" }, { text: "605" } ] },
        { kind: :body,   cells: [ { text: "Busan" }, { text: "3.4M" }, { text: "770" } ] },
        { kind: :body,   cells: [ { text: "Daegu" }, { text: "2.4M" }, { text: "884" } ] }
      ]
    }.freeze
  end
end
```

- [ ] **Step 4: Write `Design::SingleTablePdf`** (port, namespaced)

```ruby
# app/services/design/single_table_pdf.rb
require "hexapdf"
require "doc_processor_rb/core/layout/inline_table"

module Design
  class SingleTablePdf
    def self.write(path, rows:, style_hash:, page_width: 595.28, page_height: 200.0)
      new(path: path, rows: rows, style_hash: style_hash,
          page_width: page_width, page_height: page_height).write
    end

    def initialize(path:, rows:, style_hash:, page_width:, page_height:)
      @path = path
      @rows = rows
      @style_hash = style_hash
      @page_width = page_width
      @page_height = page_height
    end

    def write
      doc = HexaPDF::Document.new
      page = doc.pages.add([ 0, 0, @page_width, @page_height ])
      canvas = page.canvas

      table_width = @page_width - 60
      table = DocProcessorRb::Layout::InlineTable.new(
        rows: @rows,
        width: table_width,
        style_hash: @style_hash
      )
      table.measure
      table.draw_pdf(canvas, x: 30, y: @page_height - 30)

      doc.write(@path)
      @path
    end
  end
end
```

- [ ] **Step 5: Declare `hexapdf` in the gemspec**

In `design.gemspec`, add alongside the existing `spec.add_dependency` lines (e.g. after `doc_processor_rb`):

```ruby
  spec.add_dependency "hexapdf"
```

(ruby-vips stays transitive via `image_processing`, as `PreviewService` already relies on it — no change there.)

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/services/design/single_table_pdf_test.rb`
Expected: PASS (2 runs, 0 failures)

- [ ] **Step 7: Commit**

```bash
git add app/services/design/single_table_pdf.rb app/services/design/table_style_preview_sample.rb design.gemspec test/services/design/single_table_pdf_test.rb
git commit -m "feat(table-preview): add Design::SingleTablePdf + sample; declare hexapdf dep"
```

---

### Task 5: `Design::TableStylePreviewService` (orchestrator)

Ties resolver + sample + PDF writer + Vips into the public entry point returning a JPEG blob. Depends on Tasks 1–4.

**Files:**
- Create: `app/services/design/table_style_preview_service.rb`
- Test: `test/services/design/table_style_preview_service_test.rb`

- [ ] **Step 1: Write the failing test** (real render → non-empty JPEG bytes)

```ruby
# test/services/design/table_style_preview_service_test.rb
require "test_helper"

class Design::TableStylePreviewServiceTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "TSPS #{SecureRandom.hex(3)}", locale: "ko")
    @ts = @theme.table_styles.find_by(name: "grid")
  end

  test "renders a non-empty JPEG blob for a table style" do
    blob = Design::TableStylePreviewService.call(@theme, @ts)
    assert blob.is_a?(String) && blob.bytesize > 1000, "blob too small: #{blob&.bytesize.inspect}"
    assert_equal "\xFF\xD8".b, blob.byteslice(0, 2), "not a JPEG (missing SOI marker)"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/design/table_style_preview_service_test.rb`
Expected: FAIL — `NameError: uninitialized constant Design::TableStylePreviewService`

- [ ] **Step 3: Write the orchestrator**

```ruby
# app/services/design/table_style_preview_service.rb
require "tempfile"

module Design
  class TableStylePreviewService
    PREVIEW_DPI = 150

    def self.call(theme, table_style)
      new(theme, table_style).call
    end

    def initialize(theme, table_style)
      @theme = theme
      @table_style = table_style
    end

    def call
      style_hash = Design::TableStyleResolver.call(@theme, @table_style)

      pdf_file = Tempfile.new(%w[ts_preview .pdf])
      jpg_file = Tempfile.new(%w[ts_preview .jpg])
      begin
        Design::SingleTablePdf.write(
          pdf_file.path,
          rows: Design::TableStylePreviewSample::SAMPLE[:rows],
          style_hash: style_hash
        )
        Design::PdfToJpg.convert(pdf_file.path, jpg_file.path, dpi: PREVIEW_DPI)
        File.binread(jpg_file.path)
      ensure
        pdf_file.close!
        jpg_file.close!
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/design/table_style_preview_service_test.rb`
Expected: PASS (1 run, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/services/design/table_style_preview_service.rb test/services/design/table_style_preview_service_test.rb
git commit -m "feat(table-preview): add Design::TableStylePreviewService orchestrator"
```

---

### Task 6: Rewire `TableStylePreviewsController#show` (gem-native default, hook override, error rescue)

> **Do NOT create a new test file.** `test/controllers/design/table_styles_test.rb` already owns the preview-endpoint tests (lines 10–23) and the component-preview tests (lines 35–47). Editing them in place avoids two divergent sources of truth (reviewer I1). This task edits the **endpoint** tests (10–23); Task 7 edits the **component** tests (35–47).

**Files:**
- Modify: `app/controllers/design/table_style_previews_controller.rb`
- Modify: `test/controllers/design/table_styles_test.rb` (rewrite the no-hook endpoint test; add error + unknown-id tests; keep the existing hook-override test)

- [ ] **Step 1: Edit the existing endpoint tests** in `test/controllers/design/table_styles_test.rb`

**Keep** the hook-override test (lines 10–18, `"preview sends host-rendered jpeg when the hook is registered"`) as-is — it still tests the override path. (Its manual `ensure … = nil` is redundant given test_helper's config restore, but harmless; leave it.)

**Replace** the no-hook 404 test (lines 20–23) with a native-render test, and **add** an error-rescue test + an unknown-id test:

```ruby
  test "preview renders a jpeg natively when no hook is registered" do
    assert_nil Design.config.table_style_preview
    get design.preview_theme_table_style_path(@theme, @ts)
    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert response.body.bytesize > 1000, "native jpeg too small"
  end

  test "a render error degrades to 422, not 500" do
    Design.config.table_style_preview = ->(_t, _ts) { raise "boom" }  # restored by teardown
    get design.preview_theme_table_style_path(@theme, @ts)
    assert_response :unprocessable_entity
  end

  test "unknown table style is 404" do
    get design.preview_theme_table_style_path(@theme, 0)
    assert_response :not_found
  end
```

- [ ] **Step 2: Run the file to verify the new/edited tests fail**

Run: `bin/rails test test/controllers/design/table_styles_test.rb`
Expected: FAIL — the no-hook case currently returns `404` (`head :not_found unless blob`) and the error case isn't rescued (it would 500). The hook-override and edit/update/reset tests still pass.

- [ ] **Step 3: Rewire the controller**

```ruby
# app/controllers/design/table_style_previews_controller.rb
module Design
  class TableStylePreviewsController < Design::ApplicationController
    before_action :set_theme

    def show
      table_style = @theme.table_styles.find(params[:id])
      blob =
        if Design.config.table_style_preview
          Design.config.table_style_preview.call(@theme, table_style)
        else
          Design::TableStylePreviewService.call(@theme, table_style)
        end

      expires_now
      send_data blob, type: "image/jpeg", disposition: "inline"
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue => e
      Rails.logger.error("[design] table-style preview failed: #{e.class}: #{e.message}")
      head :unprocessable_entity
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/design/table_styles_test.rb`
Expected: PASS — the rewritten/added endpoint tests pass; the rest of the file is still green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/design/table_style_previews_controller.rb test/controllers/design/table_styles_test.rb
git commit -m "feat(table-preview): render natively in controller; hook becomes override; rescue to 422"
```

---

### Task 7: Components always render the preview `<img>` + remove the dead locale key

Drop the `if Design.config.table_style_preview` gate (and the `else` placeholder) in both the editor preview pane and the theme-show card grid. Remove the now-unused `design.table_styles.no_preview` key (keep `design.themes.no_preview`, which is a different key used by theme thumbnails).

**Files:**
- Modify: `app/components/design/views/table_styles/edit.rb` (preview_pane, ~line 22–31)
- Modify: `app/components/design/views/themes/show.rb` (table_style_card, ~line 176–192)
- Modify: `config/locales/en.yml` (remove `table_styles.no_preview`, line ~350)
- Modify: `config/locales/ko.yml` (remove `table_styles.no_preview`, line ~350)
- Modify: `test/controllers/design/table_styles_test.rb` (rewrite the placeholder test, lines 35–39; keep the hook-img test 41–47)
- Modify: `test/controllers/design/themes_show_table_styles_test.rb` (append a no-hook img test)

- [ ] **Step 1: Edit the existing component tests** (img always present; placeholder gone)

In `test/controllers/design/table_styles_test.rb`, **replace** the placeholder test (lines 35–39, `"edit shows a no-preview placeholder when no hook is registered"`) with a native-render assertion. **Keep** the hook-registered img test (lines 41–47) as-is (still valid — the img renders, hook or not).

```ruby
  test "edit renders the preview frame and img with no hook registered" do
    assert_nil Design.config.table_style_preview
    get design.edit_theme_table_style_path(@theme, @ts)
    assert_response :success
    assert_select "turbo-frame#preview_frame img[src*=?]", "preview"
    assert_not_includes response.body, "No preview"
  end
```

In `test/controllers/design/themes_show_table_styles_test.rb`, **append** (its `setup` uses `@theme`/`@ts`, `sign_in :david`):

```ruby
  test "theme show renders table-style preview images with no hook registered" do
    assert_nil Design.config.table_style_preview
    get design.theme_path(@theme)
    assert_response :success
    assert_select "img[src*=?]", "table_styles/#{@ts.id}/preview"
    assert_not_includes response.body, "No preview"
  end
```

> Asserting absence with the literal `"No preview"` (not `I18n.t`) avoids a `translation missing` raise once the key is deleted in Step 5.

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/design/themes_show_table_styles_test.rb test/controllers/design/table_styles_test.rb`
Expected: FAIL — with no hook, the components currently render the "No preview" placeholder, not the `<img>`.

- [ ] **Step 3: Rewire `table_styles/edit.rb#preview_pane`** — always render the frame+img:

```ruby
        def preview_pane
          div(class: "flex-1 min-w-0 flex items-start justify-center rounded-lg border border-slate-200 bg-slate-50 p-4") do
            turbo_frame_tag("preview_frame") do
              img(src: helpers.preview_theme_table_style_path(@theme, @table_style, t: @table_style.updated_at.to_i),
                  alt: @table_style.name, class: "max-w-full border border-slate-200 bg-white shadow-sm")
            end
          end
        end
```

- [ ] **Step 4: Rewire `themes/show.rb#table_style_card`** — always render the img (drop the `if/else`):

```ruby
            div(class: "aspect-[4/3] bg-slate-50 flex items-center justify-center overflow-hidden") do
              img(src: helpers.preview_theme_table_style_path(@theme, ts, t: ts.updated_at.to_i), alt: ts.name, class: "w-full h-full object-contain")
            end
```

- [ ] **Step 5: Remove the dead `table_styles.no_preview` key** from both locales

Both locales have **two** identically-indented `no_preview:` lines (`themes:` ≈ line 34, `table_styles:` ≈ line 350). Delete **only the one under the `table_styles:` section** — by line number / section context, **not** by string match (a text-match delete would hit both). **Keep** the `themes:` one — `themes/show.rb:148` still uses `design.themes.no_preview`. Verify the two hits and their sections first:

```bash
grep -n "no_preview" config/locales/en.yml   # two hits: ~34 (themes, keep) and ~350 (table_styles, remove)
grep -n "no_preview" config/locales/ko.yml   # same two lines
```

- [ ] **Step 6: Run the component tests + the i18n parity test**

Run: `bin/rails test test/controllers/design/themes_show_table_styles_test.rb test/controllers/design/table_styles_test.rb test/i18n`
Expected: PASS (the i18n suite confirms en/ko stay in parity after the key removal)

- [ ] **Step 7: Run the whole gem suite (full regression for the gem half)**

Run: `bin/rails test`
Expected: PASS — all green.

- [ ] **Step 8: Commit**

```bash
git add app/components/design/views/table_styles/edit.rb app/components/design/views/themes/show.rb config/locales/en.yml config/locales/ko.yml test/controllers/design/themes_show_table_styles_test.rb test/controllers/design/table_styles_test.rb
git commit -m "feat(table-preview): always render preview img in components; drop dead no_preview key"
```

> **Gem half done.** The gem now renders table previews natively. Push happens after Task 8's book_design half is verified, so book_design's `Gemfile.lock` can bump to the pushed revision in the same session if desired — but pushing the gem now (before Task 8) is also fine since book_design's deletion only *removes* a redundant override. Coordinate with the human on push timing (the spec's deploy path is separate).

---

### Task 8: book_design — delete the redundant copy + the hook (separate repo)

**Repo:** `/Users/mskim/Development/book/book_design` — `cd` there first.

The gem now provides table previews natively, so book_design's 5 services + the `Design.config.table_style_preview` registration are redundant. Delete them. The only references (verified) are `config/initializers/design.rb:17` and two service tests.

**Files:**
- Delete: `app/services/table_style_preview_renderer.rb`
- Delete: `app/services/table_style_resolver.rb`
- Delete: `app/services/single_table_pdf.rb`
- Delete: `app/services/table_style_preview_sample.rb`
- Delete: `app/services/hex_to_cmyk.rb`
- Delete: `test/services/table_style_resolver_test.rb`
- Delete: `test/services/hex_to_cmyk_test.rb`
- Modify: `config/initializers/design.rb` (remove the `c.table_style_preview = …` line — this is the only hook registration)
- Modify (maybe): `test/integration/studio_cutover_test.rb` (its preview assertion becomes gem-native once the initializer line is gone; no hook setup lives here to remove)

- [ ] **Step 1: Re-verify nothing else references the 5 services** (guard before deleting)

Run:
```bash
cd /Users/mskim/Development/book/book_design
grep -rn "TableStylePreviewRenderer\|TableStyleResolver\|SingleTablePdf\|TableStylePreviewSample\|HexToCmyk" app config lib test \
  | grep -v "app/services/\(table_style_preview_renderer\|table_style_resolver\|single_table_pdf\|table_style_preview_sample\|hex_to_cmyk\)\.rb"
```
Expected: only `config/initializers/design.rb` (the hook) and `test/services/{table_style_resolver,hex_to_cmyk}_test.rb`. **If anything else appears, STOP and report** (a new consumer would mean the deletion isn't safe).

- [ ] **Step 2: Read the cutover test's current preview assertion**

Run: `sed -n '1,40p' test/integration/studio_cutover_test.rb`. Note: the hook is registered in `config/initializers/design.rb:17`, **not** in this test — so the test itself has no hook setup to remove. It already GETs the preview path and asserts `image/jpeg`; once Step 4 removes the initializer line, that same assertion exercises the **gem-native** path and should pass unchanged. Find the existing preview assertion and confirm it expects `image/jpeg`.

- [ ] **Step 3: Confirm (don't break) the cutover preview assertion**

Leave the existing preview assertion in place — after Step 4 it tests the gem-native path. If the file has no explicit "renders natively" wording, optionally rename the test for clarity, but **do not** add hook setup. The assertion must pass **with no hook registered** (which is the state after Step 4). If the existing assertion already covers `image/jpeg` from the preview endpoint, no edit is needed here beyond Step 4.

- [ ] **Step 4: Remove the hook registration**

In `config/initializers/design.rb`, delete the line:
```ruby
  c.table_style_preview = ->(theme, table_style) { TableStylePreviewRenderer.call(theme, table_style) }
```

- [ ] **Step 5: Delete the 5 services + 2 service tests**

```bash
git rm app/services/table_style_preview_renderer.rb \
       app/services/table_style_resolver.rb \
       app/services/single_table_pdf.rb \
       app/services/table_style_preview_sample.rb \
       app/services/hex_to_cmyk.rb \
       test/services/table_style_resolver_test.rb \
       test/services/hex_to_cmyk_test.rb
```

- [ ] **Step 6: Eager-load check** (catches any dangling constant reference)

Run: `RAILS_ENV=test bin/rails runner 'Rails.application.eager_load!; puts "eager-load OK"'`
Expected: `eager-load OK` (no `NameError`).

> ⚠️ This requires book_design's `Gemfile.lock` to resolve the gem with the new services. For **local dev** the `.bundle/config` override points at the local gem checkout (which now has them on the working tree) — make sure the gem checkout is on the branch/commit with Tasks 1–7. If eager-load fails on `Design::TableStylePreviewService`, the gem half isn't visible yet (commit/rebundle the gem first).

- [ ] **Step 7: Run the cutover test + the full book_design suite**

Run: `bin/rails test test/integration/studio_cutover_test.rb` then `bin/rails test`
Expected: PASS — table previews now come from the gem; no references to the deleted services remain.
(Only `bin/rails test`. Never `db:reset`/`bin/setup`.)

- [ ] **Step 8: Commit**

```bash
git add -A app/services config/initializers/design.rb test/integration/studio_cutover_test.rb
git commit -m "refactor(table-preview): delete book_design renderer; use gem-native preview"
```

> Use the explicit paths above (not a bare `git add -A` over the whole repo) so unrelated uncommitted artifacts aren't swept in.

---

## Done criteria

- Gem: all new services exist and are tested; `TableStylePreviewsController` renders natively (hook = override; errors → 422); components always render the preview `<img>`; full gem suite green.
- book_design: 5 services + hook deleted; cutover test + full suite green with previews served gem-natively; eager-load clean.
- The two halves leave `Design.config.table_style_preview` as a working optional override; book_write/the Docker server now get table previews with zero registration.

## Follow-on (out of this plan)

- Push the gem to `mskim/design` `main`; bump book_write's `Gemfile.lock` to pick up native previews (per `book_design/docs/publishing_design_change_to_book_write.md` §1).
- The **theme-sync export/import** feature (separate spec/plan) — its import now warms table previews by calling `Design::TableStylePreviewService` directly.
- Preview caching (deferred perf pass).
