module Design
  class PreviewService
    # doc_processor_rb's DBDocument rebinds its global Sequel::Model classes to the
    # active SQLite file on every instantiation (setup_models → model.dataset = db[...]).
    # That shared global state means two DBDocuments can't be alive at once in a single
    # process without clobbering each other's model bindings (UNIQUE/readonly errors).
    # Serialize the model-touching phase of generation across all threads in the process.
    GENERATION_LOCK = Mutex.new

    PREVIEW_DPI = 150
    MAX_PREVIEW_PAGES = 4
    CACHE_VERSION = "v4" # bump when the stamp/JPG layout changes; old stamps become misses
    FALLBACK_HEADING = {
      "title" => "첫번째 이야기",
      "subtitle" => "부제목은 여기에",
      "author" => "저자명",
      "publisher" => "출판사"
    }.freeze

    FALLBACK_BOOK_TITLE = "책제목은 여기에"

    FALLBACK_BODY = <<~TEXT.freeze
      Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
    TEXT

    # Sample content for the wing panels so the studio preview shows what each wing
    # actually renders (back_wing = promotional "other books", front_wing = author
    # profile), keyed by theme locale (ko/en; others fall back to ko).
    SAMPLE_BACK_WING = {
      "ko" => {
        heading: "다른 책들",
        books: [
          { title: "바람의 기록", description: "잊혀진 도시를 둘러싼 대서사시." },
          { title: "고요한 아침", description: "일상 속에서 발견하는 작은 위로." },
          { title: "별을 세는 밤", description: "우주와 인간을 잇는 사색의 여정." }
        ]
      },
      "en" => {
        heading: "Other Books",
        books: [
          { title: "Records of the Wind", description: "An epic around a forgotten city." },
          { title: "A Quiet Morning", description: "Small comforts found in daily life." },
          { title: "Counting the Stars", description: "A meditation linking cosmos and self." }
        ]
      }
    }.freeze

    SAMPLE_FRONT_WING = {
      "ko" => { name: "홍길동",
                bio: Array.new(5) { "여기는 저자의 대한 소개 부분입니다. " * 10 }.join("\n") },
      "en" => { name: "Jane Doe",
                bio: "Novelist and translator. Author of several novels and essay collections, known for a delicate attention to the texture of everyday life." }
    }.freeze

    # Solid pastel fills for the generated sample book covers (RGB), cycled by index.
    SAMPLE_COVER_COLORS = [ [ 236, 72, 153 ], [ 59, 130, 246 ], [ 16, 185, 129 ], [ 245, 158, 11 ], [ 139, 92, 246 ] ].freeze

    # 날개 (cover flaps) are a fixed-width strip folded behind the cover — not the full
    # book page. Preview them at this flap width (full book height), not the book width.
    WING_FLAP_WIDTH_MM = 100

    attr_reader :document_design, :paper_size

    # print_mode: render as the printed book does (인쇄용): the body text box
    # adds the binding margin on the spine side (odd pages left, even pages
    # right; preview page 1 is odd). Only BINDING_DOC_TYPES use it; elsewhere
    # it is off, so those doc types keep a single cache.
    def initialize(document_design, paper_size: nil, print_mode: false)
      @document_design = document_design
      @paper_size = paper_size || document_design.paper_size
      @print_mode = print_mode == true && document_design.binding_applies?
    end

    def print_mode? = @print_mode

    # Generate preview: PDF → up to MAX_PREVIEW_PAGES JPGs + per-page overlay data
    # Returns { success:, page_count:, pages: [{ jpg_path:, overlay_data: }], page_width:, page_height:, print_mode:, error: }
    # jpg_path/overlay_data are also present as page-1 aliases for callers that only show the first page.
    def generate
      cached = load_cached_preview
      return cached if cached

      FileUtils.mkdir_p(preview_dir)

      # Render into a private per-call working dir, then atomically publish the
      # JPG + cache stamp into preview_dir. Two requests for the same document can
      # overlap (lazy preview frame + a save), and a shared working dir let one
      # request's rm_rf/recreate corrupt the other's half-written SQLite DB. The
      # working dir sits under tmp/previews so the final rename stays on one FS.
      work = work_dir
      FileUtils.mkdir_p(work)
      @work_dir = work # sample wing covers/photos are generated here, read back at render time

      db_path = File.join(work, "preview.db")
      pdf_path = File.join(work, "preview.pdf")

      db_doc = nil
      pages = nil
      begin
        # The DB build, PDF render, and overlay read all go through doc_processor's
        # global Sequel models, so they must run one-at-a-time per process.
        GENERATION_LOCK.synchronize do
          db_doc = create_db_document(db_path)
          populate_database(db_doc)
          generate_pdf(db_doc, pdf_path)
          # Per-page overlays must be read while the DBDocument is open (inside the lock).
          pages = extract_pages_overlay_data(db_doc)
        ensure
          db_doc&.close # release the connection before the next thread rebinds the models
          db_doc = nil
        end

        # Rasterize (libvips, no Sequel models — safe outside the lock) into the work dir,
        # then publish page by page + the stamp that validates them.
        rendered = convert_pdf_to_jpgs(pdf_path, work)
        raise "no pages rasterized from #{pdf_path}" if rendered.zero?
        # DB page rows and the PDF can disagree (wings never save_page); trust what was actually rasterized.
        pages = pages.first(rendered)
        publish_pages(work, pages.size)
        save_cache_stamp(pages)

        result_hash(pages)
      rescue => e
        Rails.logger.error "DesignPreviewService error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        { success: false, page_count: 0, pages: [], jpg_path: nil, overlay_data: [],
          page_width: preview_page_width_pt, page_height: paper_size.height_pt, print_mode: @print_mode, error: e.message }
      ensure
        db_doc&.close
        FileUtils.rm_rf(work)
      end
    end

    # Page-1 JPG (kept for callers that only ever show the first page: cards, gallery).
    def jpg_path = page_jpg_path(1)

    def page_jpg_path(page) = File.join(preview_dir, "preview_#{page}.jpg")

    def clear_cache
      FileUtils.rm_rf(preview_dir)
    end

    private

    # The design's grid line (its own body_line_count, else the paper size's):
    # the engine's master page uses it, so text, headings and the grid share it.
    def body_line_height = document_design.body_line_height

    # Print mode renders into a subfolder, so publish_pages' preview_*.jpg glob
    # never sees the other mode's pages, and a normal clear_cache removes both.
    def preview_dir
      base = Rails.root.join("tmp", "previews", "dd_#{document_design.id}")
      @print_mode ? base.join("print") : base
    end

    # Private per-call working dir (unique per generation) so concurrent renders of
    # the same document never share a SQLite DB. Under tmp/previews so the published
    # JPG rename stays on a single filesystem (atomic).
    def work_dir
      Rails.root.join("tmp", "previews", ".work", "dd_#{document_design.id}_#{SecureRandom.hex(8)}")
    end

    # Styles resolve theme base → chapter → this design, so the chapter layer is
    # part of the key. Row counts catch deletions, which don't bump max(updated_at).
    def cache_fingerprint
      chapter = document_design.chapter_design
      timestamps = [
        document_design.updated_at,
        paper_size.updated_at,
        paper_size.theme.updated_at,
        document_design.paragraph_styles.maximum(:updated_at),
        document_design.heading_elements.maximum(:updated_at),
        paper_size.theme.base_paragraph_styles.maximum(:updated_at),
        chapter&.paragraph_styles&.maximum(:updated_at),
        document_design.paragraph_styles.count,
        chapter&.paragraph_styles&.count
      ].compact
      # Sub-second precision: two edits within the same second must not collide.
      parts = timestamps.map { |t| t.respond_to?(:iso8601) ? t.iso8601(6) : t.to_s }
      # The normal key is unchanged (existing caches stay warm); print mode adds a part.
      "#{CACHE_VERSION}:" + Digest::MD5.hexdigest((parts + [ sample_content.fingerprint, ("print" if @print_mode) ].compact).join("-"))
    end

    def cache_stamp_path
      File.join(preview_dir, "cache_stamp.json")
    end

    def load_cached_preview
      return nil unless File.exist?(cache_stamp_path)
      stamp = JSON.parse(File.read(cache_stamp_path))
      return nil unless stamp["fingerprint"] == cache_fingerprint && stamp["pages"].is_a?(Array)
      count = stamp["pages"].size
      return nil unless count.positive? && (1..count).all? { |n| File.exist?(page_jpg_path(n)) }

      pages = stamp["pages"].each_with_index.map do |pg, i|
        { jpg_path: page_jpg_path(i + 1), overlay_data: Array(pg["overlay_data"]).map(&:symbolize_keys) }
      end
      result_hash(pages)
    rescue JSON::ParserError, NoMethodError, TypeError
      nil
    end

    def save_cache_stamp(pages)
      File.write(cache_stamp_path, {
        fingerprint: cache_fingerprint,
        page_count: pages.size,
        pages: pages.map { |pg| { overlay_data: pg[:overlay_data] } }
      }.to_json)
    end

    def result_hash(pages)
      {
        success: true,
        page_count: pages.size,
        pages: pages,
        jpg_path: pages.first&.dig(:jpg_path),
        overlay_data: pages.first&.dig(:overlay_data) || [],
        page_width: preview_page_width_pt,
        page_height: paper_size.height_pt,
        print_mode: @print_mode,
        error: nil
      }
    end

    # Move preview_1..N.jpg from the work dir into preview_dir (atomic per file, same FS)
    # and drop any stale higher-numbered pages from a previous, longer render. Overlapping
    # generations of the same document glob the same stale files, so rm_f (not delete):
    # the loser must not fail the whole preview over a file the winner already removed.
    def publish_pages(work, count)
      (1..count).each { |n| File.rename(File.join(work, "preview_#{n}.jpg"), page_jpg_path(n)) }
      Dir[File.join(preview_dir, "preview_*.jpg")].each do |f|
        n = f[/preview_(\d+)\.jpg\z/, 1].to_i
        FileUtils.rm_f(f) if n > count
      end
    end

    def create_db_document(db_path)
      File.delete(db_path) if File.exist?(db_path)
      DocProcessorRb::Database::DBDocument.new(path: db_path, create_if_needed: true)
    end

    def populate_database(db_doc)
      populate_document(db_doc)
      populate_master_page(db_doc)
      if wing?
        # Wing panels read component-scoped blocks + bare-named styles, not the
        # generic heading/body/toc sample content.
        populate_wing_styles(db_doc)
        populate_wing_blocks(db_doc)
      else
        populate_heading_items(db_doc)
        populate_paragraph_styles(db_doc)
        populate_toc_items(db_doc)
        populate_sample_blocks(db_doc)
      end
      populate_header_footer_slots(db_doc)
    end

    def populate_document(db_doc)
      ps = paper_size
      dd = document_design

      heading_data = {}
      placeholders = heading_placeholder
      if dd.doc_type == "toc"
        # TOC: use sample content title for heading (e.g. "차례", "Table of Contents")
        heading_data[:title] = sample_content.title
      elsif dd.heading_elements.any?
        dd.heading_elements.each do |el|
          heading_data[el.element_type.to_sym] = placeholders[el.element_type] || el.element_type.capitalize
        end
      elsif resolved_doc_type.uses_page_heading?
        placeholders.each { |k, v| heading_data[k.to_sym] = v }
      elsif dd.heading_height_in_lines.to_i > 0
        # Chapter-like types: provide default heading title for the heading area
        heading_data[:title] = placeholders["title"] || FALLBACK_HEADING["title"]
      end

      # Include book_title for header/footer interpolation
      heading_data[:book_title] = FALLBACK_BOOK_TITLE

      doc = db_doc.document_info
      doc.update(
        doc_type: dd.doc_type,
        page_width: preview_page_width_pt,
        page_height: ps.height_pt,
        margin_top: ps.top_margin_pt,
        margin_bottom: ps.bottom_margin_pt,
        margin_left: ps.left_margin_pt,
        margin_right: ps.right_margin_pt,
        binding_margin: ps.binding_margin_pt,
        paper_size: ps.size_name,
        body_font: theme.base_body_font,
        body_font_size: theme.base_body_font_size,
        body_line_height: body_line_height,
        heading: heading_data.to_json
      )

      # Set text_box positioning via raw SQL to avoid Sequel column cache issues
      db = db_doc.instance_variable_get(:@db)
      extra_attrs = {
        text_box_anchor_position: dd.effective_text_box_anchor_position,
        text_box_grid_width: dd.effective_text_box_grid_width,
        text_box_grid_height: dd.effective_text_box_grid_height
      }
      if dd.page_bg_color.present? && db[:documents].columns.include?(:page_bg_color)
        extra_attrs[:page_bg_color] = dd.page_bg_color
      end
      db[:documents].where(id: doc.id).update(extra_attrs)
    end

    def populate_master_page(db_doc)
      ps = paper_size
      dd = document_design

      mp = db_doc.master_page
      mp.update(
        width: preview_page_width_pt,
        height: ps.height_pt,
        left_margin: ps.left_margin_pt,
        top_margin: ps.top_margin_pt,
        right_margin: ps.right_margin_pt,
        bottom_margin: ps.bottom_margin_pt,
        binding_margin: ps.binding_margin_pt,
        body_line_count: dd.body_line_count,
        body_line_height: dd.body_line_height,
        column_count: dd.column_count,
        gutter: dd.gutter,
        heading_height_in_lines: dd.heading_height_in_lines.to_i > 0 ? dd.heading_height_in_lines : 0,
        heading_v_align: dd.heading_v_align || (resolved_doc_type.uses_page_heading? ? "top" : "center"),
        toc_v_align: dd.effective_toc_v_align
      )
    end

    def populate_heading_items(db_doc)
      elements = document_design.heading_elements.to_a

      # If no heading elements configured but using page heading renderer,
      # add default sample items so the preview isn't blank
      placeholders = heading_placeholder
      if elements.empty? && resolved_doc_type.uses_page_heading?
        placeholders.each do |item_type, content|
          DocProcessorRb::Database::Models::HeadingItem.create(
            document_id: 1,
            item_type: item_type,
            item_content: content
          )
        end
      elsif elements.empty? && document_design.heading_height_in_lines.to_i > 0
        # Chapter-like types with heading area but no heading elements:
        # add a default title so the heading zone isn't blank
        DocProcessorRb::Database::Models::HeadingItem.create(
          document_id: 1,
          item_type: "title",
          item_content: placeholders["title"] || FALLBACK_HEADING["title"]
        )
      else
        elements.each do |el|
          content = placeholders[el.element_type] || el.element_type.capitalize
          DocProcessorRb::Database::Models::HeadingItem.create(
            document_id: 1,
            item_type: el.element_type,
            item_content: content
          )
        end
      end
    end

    def populate_paragraph_styles(db_doc)
      # Clear default styles and insert merged styles from document_design
      db_doc.instance_variable_get(:@db)[:paragraph_styles].delete

      merged = document_design.merged_paragraph_styles
      merged.each do |style|
        attrs = build_style_attrs(style)

        DocProcessorRb::Database::Models::ParagraphStyle.create(
          name: style.name,
          display_name: style.korean_name || style.name,
          attributes: attrs.to_json
        )
      end

      # TitlePageRenderer looks up styles as h1/h2/h3/body, not title/subtitle/author/publisher.
      # Overwrite h1/h2/h3/body with heading element style values for title page types.
      if resolved_doc_type.uses_page_heading?
        style_aliases = { "title" => "h1", "subtitle" => "h2", "author" => "h3", "publisher" => "body" }
        db = db_doc.instance_variable_get(:@db)

        style_aliases.each do |source_name, target_name|
          source = merged.find { |s| s.name == source_name }
          next unless source

          attrs = build_style_attrs(source, default_align: "center", first_line_indent: 0.0)

          # Delete existing style with this name, then create with heading element values
          db[:paragraph_styles].where(name: target_name).delete
          DocProcessorRb::Database::Models::ParagraphStyle.create(
            name: target_name,
            display_name: source.korean_name || target_name,
            attributes: attrs.to_json
          )
        end
      end

      # Ensure body style exists
      unless merged.any? { |s| s.name == "body" }
        DocProcessorRb::Database::Models::ParagraphStyle.create(
          name: "body",
          display_name: "Body Text",
          attributes: {
            font_family: theme.base_body_font,
            font_size: theme.base_body_font_size,
            font_weight: "normal",
            font_style: "normal",
            color: "#000000",
            text_align: "left",
            line_height: body_line_height,
            first_line_indent: 0.0,
            is_monospace: false
          }.to_json
        )
      end
    end

    def populate_sample_blocks(db_doc)
      doc_type = resolved_doc_type
      seq = 1

      # For types that use page headings (title_page, part_cover, front_page),
      # add heading element blocks
      placeholders = heading_placeholder
      if doc_type.uses_page_heading? && document_design.heading_height_in_lines.to_i > 0
        document_design.heading_elements.each do |el|
          content = placeholders[el.element_type] || el.element_type.capitalize
          db_doc.add_block(
            sequence: seq,
            content: content,
            block_type: el.element_type
          )
          seq += 1
        end
      end

      # For types that use a text box (chapter, inside_cover, copyright, poem, etc.),
      # add body text blocks. Types like title_page, blank_page, part_cover skip this.
      # TOC uses toc_items table instead of body text blocks.
      return unless doc_type.needs_text_box?
      return if document_design.doc_type == "toc"

      # Enough to overflow into page 2–3 for multi-page types; the preview is capped at
      # MAX_PREVIEW_PAGES anyway, so 6× only made the PDF slower to render.
      repeat = document_design.doc_type == "copyright" ? 1 : 2
      paragraphs = body_paragraphs
      repeat.times do
        paragraphs.each do |para|
          text = para.strip
          block_type = if text.start_with?("## ")
            text = text.sub(/\A##\s+/, "")
            "h2"
          else
            "body"
          end

          # Insert blank lines before h2 based on its space_before_in_lines
          if block_type == "h2"
            h2_style = document_design.merged_paragraph_styles.find { |s| s.name == "h2" }
            lines_before = h2_style&.space_before_in_lines.to_i
            lines_before.times do
              db_doc.add_block(sequence: seq, content: "", block_type: "body")
              seq += 1
            end
          end

          db_doc.add_block(
            sequence: seq,
            content: text,
            block_type: block_type
          )
          seq += 1
        end
      end
    end

    def populate_toc_items(db_doc)
      return unless document_design.doc_type == "toc"

      content = sample_content
      return unless content.exists?

      lines = content.raw.strip.lines
      # Skip the # [toc] Title line
      lines.shift if lines.first&.match?(/\A#\s+\[/)

      seq = 0
      lines.each do |line|
        line = line.strip
        next if line.blank?
        # Format: ## level:title:page_number
        next unless line.start_with?("## ")

        entry = line.sub(/\A##\s+/, "")
        parts = entry.split(":", 3)
        next unless parts.length == 3

        level = parts[0].to_i
        title = parts[1].strip
        page_num = parts[2].strip.to_i

        seq += 1
        DocProcessorRb::Database::Models::TocItem.create(
          document_id: 1,
          heading_level: level,
          title: title,
          page_number: page_num,
          sequence: seq
        )
      end
    end

    def populate_header_footer_slots(db_doc)
      dd = document_design
      db = db_doc.instance_variable_get(:@db)

      return unless db.table_exists?(:header_footer_slots)

      slots = []
      if dd.has_header
        slots << { slot_name: "header_left", y_offset: dd.header_left_y_offset || 10.0,
                   content_string: dd.header_left_content_string }
        slots << { slot_name: "header_right", y_offset: dd.header_right_y_offset || 10.0,
                   content_string: dd.header_right_content_string }
      end
      if dd.has_footer
        slots << { slot_name: "footer_left", y_offset: dd.footer_left_y_offset || 10.0,
                   content_string: dd.footer_left_content_string }
        slots << { slot_name: "footer_right", y_offset: dd.footer_right_y_offset || 10.0,
                   content_string: dd.footer_right_content_string }
      end

      show_first = dd.show_header_footer_on_first_page ? 1 : 0
      slots.each do |slot|
        next if slot[:content_string].blank?

        db[:header_footer_slots].insert(
          document_id: 1,
          slot_name: slot[:slot_name],
          y_offset: slot[:y_offset].to_f,
          x_offset: 0.0,
          content_string: slot[:content_string],
          show_on_first_page: show_first
        )
      end
    end

    def generate_pdf(db_doc, pdf_path)
      doc_info = db_doc.document_info
      component = if wing?
        # Wing renderers extend BaseRenderer (options: keyword), not the DocLayout
        # components (**options), so they're instantiated separately.
        wing_renderer_class.new(db_document: db_doc, doc_info: doc_info, options: { svg: true })
      else
        doc_layout_class.new(db_document: db_doc, doc_info: doc_info, svg: true, print_mode: @print_mode)
      end

      component.render_to_pdf(pdf_path)

      # Page background: DocumentCover component handles it via preview DB;
      # for all other doc types, inject via content stream.
      if document_design.page_bg_color.present? && document_design.doc_type != "document_cover"
        inject_page_background(pdf_path)
      end

      inject_heading_background(pdf_path) if heading_bg_color_present?
    end

    BLEED_PT = 3 * 72.0 / 25.4  # 3mm in points

    def inject_page_background(pdf_path)
      require "hexapdf"
      ps = paper_size
      color = parse_color_to_cmyk(document_design.page_bg_color)

      # Insert page bg BEFORE text commands but AFTER any white fill from the component
      c, m, y, k = color.map { |v| v / 100.0 }
      bg_commands = "q\n"
      bg_commands += "#{c} #{m} #{y} #{k} k\n"
      bg_commands += "#{-BLEED_PT} #{-BLEED_PT} #{ps.width_pt + 2 * BLEED_PT} #{ps.height_pt + 2 * BLEED_PT} re\n"
      bg_commands += "f\nQ\n"

      doc = HexaPDF::Document.open(pdf_path)
      # Every page carries the background, not just the first (the preview shows several).
      doc.pages.each do |page|
        contents_ref = page[:Contents]

        existing_stream = if contents_ref.is_a?(Array)
          contents_ref.map { |ref| ref.stream }.join("\n")
        else
          contents_ref.stream
        end

        # Find where text content starts (first /F or BT command)
        text_start = existing_stream.index(%r{^/F}m) || existing_stream.index(/^BT/m)
        if text_start
          new_stream = existing_stream[0...text_start] + bg_commands + existing_stream[text_start..]
        else
          new_stream = existing_stream + bg_commands
        end

        new_obj = doc.add({}, stream: new_stream)
        page[:Contents] = new_obj
      end

      tmp_path = "#{pdf_path}.tmp"
      doc.write(tmp_path)
      FileUtils.mv(tmp_path, pdf_path)
    rescue => e
      Rails.logger.error "inject_page_background error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end

    def build_style_attrs(style, default_align: "left", first_line_indent: nil)
      {
        font_family: style.font || theme.base_body_font,
        font_size: style.font_size&.to_f || theme.base_body_font_size,
        font_weight: style.bold_font.present? ? "bold" : "normal",
        font_style: "normal",
        color: style.text_color || "CMYK=0,0,0,100",
        text_align: style.text_align || default_align,
        line_height: style.text_line_spacing&.to_f || body_line_height,
        tracking: style.tracking&.to_f,
        space_width: style.space_width&.to_f,
        text_scale: style.scale&.to_f,
        margin_top: style.space_before&.to_f || 0.0,
        margin_bottom: style.space_after&.to_f || 0.0,
        padding_left: style.left_indent&.to_f || 0.0,
        padding_right: style.right_indent&.to_f || 0.0,
        padding_top: style.padding_top&.to_f || 0.0,
        padding_bottom: style.padding_bottom&.to_f || 0.0,
        space_before_in_lines: style.space_before_in_lines&.to_i || 0,
        space_after_in_lines: style.space_after_in_lines&.to_i || 0,
        first_line_indent: first_line_indent || style.first_line_indent&.to_f || 0.0,
        is_monospace: false,
        bold_font_family: style.bold_font,
        bold_color: style.bold_text_color,
        emphasis_font_family: style.emphasis_font,
        emphasis_color: style.emphasis_color,
        fill_type: style.fill_type,
        fill_color: style.fill_color,
        fill_ending_color: style.fill_ending_color,
        fill_gradient_direction: style.fill_gradient_direction,
        border_thickness: style.border_thickness&.to_f,
        border_color: style.border_color,
        border_side: style.border_side.presence || (style.border_thickness.to_f > 0 ? "1,1,1,1" : nil),
        rounded_corners: style.rounded_corners.presence || (style.corner_radius.present? ? "1,1,1,1" : nil),
        corner_radius: style.corner_radius
      }
    end

    def heading_bg_color_present?
      dd = document_design
      dd.heading_bg_type == "color" && dd.heading_bg_color.present? && dd.heading_bg_color != "white" && dd.heading_bg_color != "#ffffff"
    end

    def inject_heading_background(pdf_path)
      require "hexapdf"
      dd = document_design
      heading_lines = dd.heading_height_in_lines || 0
      line_height = body_line_height
      return if heading_lines <= 0

      heading_height = heading_lines * line_height
      ps = paper_size
      v_align = dd.heading_v_align || "center"

      # Calculate heading zone position.
      # Two rendering paths:
      #   - Heading component (chapter, toc, etc.): zone is always at top of page
      #   - PageHeading component (title_page, part_cover, etc.): zone position depends on v_align
      #
      # PDF coords: origin at bottom-left, Y increases upward.

      uses_page_heading = resolved_doc_type.uses_page_heading?

      if uses_page_heading
        # PageHeading: v_align controls zone position on the full page
        case v_align
        when "top"
          rect_y = ps.height_pt - ps.top_margin_pt - heading_height
          rect_h = ps.top_margin_pt + heading_height
        when "bottom"
          rect_y = 0
          rect_h = ps.bottom_margin_pt + heading_height
        else # center
          rect_y = (ps.height_pt - heading_height) / 2.0
          rect_h = heading_height
        end
      else
        # Heading (chapter etc.): zone is inside the text_box, from top_margin down for heading_height
        rect_y = ps.height_pt - ps.top_margin_pt - heading_height
        rect_h = heading_height
      end

      color = parse_color_to_cmyk(dd.heading_bg_color)

      doc = HexaPDF::Document.open(pdf_path)
      page = doc.pages[0]
      contents_ref = page[:Contents]

      existing_stream = if contents_ref.is_a?(Array)
        contents_ref.map { |ref| ref.stream }.join("\n")
      else
        contents_ref.stream
      end

      # Insert heading bg BEFORE text commands (BT or /F) but AFTER page background
      c, m, y, k = color.map { |v| v / 100.0 }
      bg_commands = "q\n"
      bg_commands += "#{c} #{m} #{y} #{k} k\n"
      bg_commands += "0 #{rect_y} #{ps.width_pt} #{rect_h} re\n"
      bg_commands += "f\nQ\n"

      # Find where text content starts (first /F or BT command)
      text_start = existing_stream.index(%r{^/F}m) || existing_stream.index(/^BT/m)
      if text_start
        new_stream = existing_stream[0...text_start] + bg_commands + existing_stream[text_start..]
      else
        new_stream = existing_stream + bg_commands
      end

      new_obj = doc.add({}, stream: new_stream)
      page[:Contents] = new_obj

      tmp_path = "#{pdf_path}.tmp"
      doc.write(tmp_path)
      FileUtils.mv(tmp_path, pdf_path)
    rescue => e
      Rails.logger.error "inject_heading_background error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end

    def parse_cmyk_color(color_str)
      parse_color_to_cmyk(color_str)
    end

    # Unified color parser: handles CMYK=, #hex, and named colors → [C,M,Y,K] (0-100 scale)
    def parse_color_to_cmyk(color_str)
      return [0, 0, 0, 100] if color_str.nil? || color_str.to_s.strip.empty?

      str = color_str.to_s.strip

      # CMYK= format
      if str.start_with?("CMYK=")
        parts = str.sub("CMYK=", "").split(",").map(&:to_f)
        return parts if parts.length == 4
      end

      # Hex color
      if str.start_with?("#") && str.length == 7
        r = str[1..2].to_i(16) / 255.0
        g = str[3..4].to_i(16) / 255.0
        b = str[5..6].to_i(16) / 255.0
        k = 1.0 - [r, g, b].max
        if k >= 1.0
          return [0.0, 0.0, 0.0, 100.0]
        else
          c = (1.0 - r - k) / (1.0 - k) * 100.0
          m = (1.0 - g - k) / (1.0 - k) * 100.0
          y = (1.0 - b - k) / (1.0 - k) * 100.0
          return [c, m, y, k * 100.0]
        end
      end

      # Named colors
      case str.downcase
      when "black"        then [0, 0, 0, 100]
      when "red"          then [0, 100, 100, 0]
      when "blue"         then [100, 100, 0, 0]
      when "green"        then [100, 0, 100, 0]
      when "white"        then [0, 0, 0, 0]
      when "gray", "grey" then [0, 0, 0, 50]
      else [0, 0, 0, 100]
      end
    end

    DOC_LAYOUT_MAP = {
      "chapter"      => DocProcessorRb::DocLayout::Book::Chapter,
      "title_page"   => DocProcessorRb::DocLayout::Book::TitlePage,
      "inside_cover" => DocProcessorRb::DocLayout::Book::InsideCover,
      "part_cover"   => DocProcessorRb::DocLayout::Book::PartCover,
      "toc"          => DocProcessorRb::DocLayout::Book::Toc,
      "blank_page"   => DocProcessorRb::DocLayout::Book::BlankPage,
      "copyright"    => DocProcessorRb::DocLayout::Book::Copyright,
      "poem"         => DocProcessorRb::DocLayout::Book::Poem,
      "document_cover" => DocProcessorRb::DocLayout::Book::DocumentCover
    }.freeze

    def doc_layout_class
      type_name = case document_design.doc_type
      when "foreword", "prologue", "epilogue", "appendix", "help", "information"
        "chapter"
      when "thanks", "dedication"
        "title_page"
      when "document_cover"
        "document_cover"
      else
        document_design.doc_type
      end

      DOC_LAYOUT_MAP.fetch(type_name, DocProcessorRb::DocLayout::Book::Chapter)
    end

    def convert_pdf_to_jpgs(pdf_path, dir)
      Design::PdfToJpg.convert_pages(pdf_path, dir, max_pages: MAX_PREVIEW_PAGES, dpi: PREVIEW_DPI)
    end

    def synthesize_toc_heading_overlay
      ps = paper_size
      dd = document_design
      heading_h = dd.heading_height_in_lines * body_line_height

      # TOC renderer always places heading at the top of the content area
      heading_x = ps.left_margin_pt
      heading_y = ps.top_margin_pt
      heading_w = ps.width_pt - ps.left_margin_pt - ps.right_margin_pt
      title_text = sample_content.title.presence || "Contents"

      [
        {
          type: "heading_area",
          x: heading_x, y: heading_y,
          width: heading_w, height: heading_h,
          markup: "heading", content_preview: "Heading Area",
          is_continuation: false
        },
        {
          type: "heading_title",
          x: heading_x, y: heading_y,
          width: heading_w, height: heading_h,
          markup: "title", content_preview: title_text,
          is_continuation: false
        }
      ]
    end

    # One entry per page up to the cap, each with that page's overlays (an empty array for
    # pages the renderer wrote no rows for). The DBDocument must still be open. `generate`
    # trims the list to what libvips actually rasterized — the PDF, not the renderer's
    # `pages` table, is the source of truth for the page count. The TOC renderer emits no
    # heading overlay, so synthesize one on page 1.
    def extract_pages_overlay_data(db_doc)
      (1..MAX_PREVIEW_PAGES).map do |page_number|
        overlays = overlay_rows(db_doc.block_overlays(document_id: 1, page_number: page_number))
        if page_number == 1 && document_design.doc_type == "toc" && document_design.heading_height_in_lines.to_i > 0
          overlays = synthesize_toc_heading_overlay + overlays
        end
        { jpg_path: page_jpg_path(page_number), overlay_data: overlays }
      end
    end

    def overlay_rows(overlays)
      overlays.map do |o|
        { type: o.overlay_type, x: o.rendered_x.to_f, y: o.rendered_y.to_f,
          width: o.rendered_width.to_f, height: o.rendered_height.to_f,
          markup: o.markup, content_preview: o.content_preview, is_continuation: o.is_continuation == 1 }
      end
    end

    def resolved_doc_type
      @resolved_doc_type ||= begin
        type_name = case document_design.doc_type
        when "foreword", "prologue", "epilogue", "appendix", "help", "information"
          "chapter"
        when "thanks", "dedication", "inside_cover", "part_cover", "document_cover"
          "title_page"
        else
          document_design.doc_type
        end

        unless DocProcessorRb::DocumentTypes::DocumentType.valid?(type_name)
          type_name = "chapter"
        end

        DocProcessorRb::DocumentTypes::DocumentType.new(type_name)
      end
    end

    def theme
      @theme ||= paper_size.theme
    end

    def sample_content
      @sample_content ||= Design::SampleContent.for(doc_type: document_design.doc_type, locale: theme.locale)
    end

    def heading_placeholder
      hash = sample_content.heading_hash.transform_keys(&:to_s)
      hash.present? ? hash : FALLBACK_HEADING
    end

    def body_paragraphs
      paragraphs = sample_content.body_paragraphs
      paragraphs.present? ? paragraphs : FALLBACK_BODY.strip.split("\n").reject(&:blank?)
    end

    # --- Wing panels (back_wing / front_wing) -------------------------------

    def wing?
      Design::DocumentDesign::WING_PANEL_TYPES.include?(document_design.doc_type)
    end

    # Page width used for layout, the master page, and the overlay/aspect. Wings
    # render at the fixed flap width; every other doc_type uses the book page width.
    def preview_page_width_pt
      wing? ? WING_FLAP_WIDTH_MM * Design::PaperSize::MM2PT : paper_size.width_pt
    end

    def wing_renderer_class
      case document_design.doc_type
      when "back_wing"  then DocProcessorRb::DocumentTypes::BackWingRenderer
      when "front_wing" then DocProcessorRb::DocumentTypes::FrontWingRenderer
      end
    end

    def wing_locale
      loc = theme.locale.to_s
      SAMPLE_BACK_WING.key?(loc) ? loc : "ko"
    end

    def back_wing_sample
      SAMPLE_BACK_WING[wing_locale]
    end

    def front_wing_sample
      SAMPLE_FRONT_WING[wing_locale]
    end

    # Insert component-scoped sample blocks matching what book_write's cover
    # pipeline builds, so the wing renderers lay out real-looking content.
    def populate_wing_blocks(db_doc)
      db = db_doc.instance_variable_get(:@db)
      document_design.doc_type == "back_wing" ? populate_back_wing_blocks(db) : populate_front_wing_blocks(db)
    end

    def populate_back_wing_blocks(db)
      sample = back_wing_sample
      db[:paragraphs].insert(
        document_id: 1, component: "back_wing", sequence: 0,
        content: sample[:heading], block_type: "heading", markup: "back_wing.heading"
      )
      sample[:books].each_with_index do |book, idx|
        db[:paragraphs].insert(
          document_id: 1, component: "back_wing", sequence: idx + 1,
          content: book[:title], block_type: "promoted_item", markup: "back_wing.item",
          metadata: { description: book[:description], image_path: sample_cover_image(idx), from_book: true }.to_json
        )
      end
    end

    def populate_front_wing_blocks(db)
      sample = front_wing_sample
      dd = document_design
      db[:paragraphs].insert(
        document_id: 1, component: "front_wing", sequence: 0,
        content: sample[:name], block_type: "heading", markup: "front_wing.author_name",
        metadata: {
          image_path: sample_photo_image,
          photo_grid_w: dd.photo_grid_width, photo_grid_h: dd.photo_grid_height,
          photo_anchor: dd.photo_anchor, photo_fit: dd.photo_fit,
          photo_border_width: dd.photo_border_width,
          photo_border_color: photo_border_hex(dd.photo_border_color)
        }.compact.to_json
      )
      db[:paragraphs].insert(
        document_id: 1, component: "front_wing", sequence: 1,
        content: sample[:bio], block_type: "body", markup: "front_wing.author_bio"
      )
    end

    # Border color as a "#rrggbb" hex the renderer can stroke (it doesn't parse
    # CMYK). nil/blank → nil so the metadata key is dropped and no border draws.
    def photo_border_hex(color)
      c = color.to_s.strip
      return nil if c.empty?
      return c if c.start_with?("#")
      if c.start_with?("CMYK=") && (parts = c.sub("CMYK=", "").split(",").map(&:to_f)).length == 4
        cc, m, y, k = parts.map { |v| v / 100.0 }
        return "#%02x%02x%02x" % [
          ((1 - cc) * (1 - k) * 255).round.clamp(0, 255),
          ((1 - m) * (1 - k) * 255).round.clamp(0, 255),
          ((1 - y) * (1 - k) * 255).round.clamp(0, 255)
        ]
      end
      nil
    end

    # Bare-named heading/title/body styles the wing renderer expects, fed from the
    # theme's plain title/body styles (wings reuse those, not wing-specific ones).
    # Absent styles fall back to the renderers' own built-in defaults.
    WING_STYLE_SOURCES = { "heading" => "title", "title" => "title", "body" => "body" }.freeze

    def populate_wing_styles(db_doc)
      db = db_doc.instance_variable_get(:@db)
      db[:paragraph_styles].delete
      merged = document_design.merged_paragraph_styles.index_by(&:name)
      WING_STYLE_SOURCES.each do |bare_name, theme_name|
        style = merged[theme_name]
        next unless style
        DocProcessorRb::Database::Models::ParagraphStyle.create(
          name: bare_name,
          display_name: bare_name,
          attributes: build_style_attrs(style).to_json
        )
      end
    end

    def sample_cover_image(index)
      color = SAMPLE_COVER_COLORS[index % SAMPLE_COVER_COLORS.size]
      write_solid_image("sample_cover_#{index}.jpg", 200, 280, color)
    end

    # A real placeholder portrait (bundled with the gem) so the front-wing preview
    # shows a photo the crop/fit/border settings read against — not a flat block.
    SAMPLE_AUTHOR_PHOTO = Design::Engine.root.join("db", "sample_content", "sample_author.jpg").freeze

    def sample_photo_image
      SAMPLE_AUTHOR_PHOTO.to_s
    end

    # Generate a solid-color placeholder image with Vips into the per-call work dir.
    def write_solid_image(name, width, height, rgb)
      path = File.join(@work_dir, name)
      (Vips::Image.black(width, height, bands: 3) + rgb).cast("uchar").jpegsave(path, Q: 80)
      path
    end
  end
end
