module Design
  class PreviewService
    # doc_processor_rb's DBDocument rebinds its global Sequel::Model classes to the
    # active SQLite file on every instantiation (setup_models → model.dataset = db[...]).
    # That shared global state means two DBDocuments can't be alive at once in a single
    # process without clobbering each other's model bindings (UNIQUE/readonly errors).
    # Serialize the model-touching phase of generation across all threads in the process.
    GENERATION_LOCK = Mutex.new

    PREVIEW_DPI = 150
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

    attr_reader :document_design, :paper_size

    def initialize(document_design, paper_size: nil)
      @document_design = document_design
      @paper_size = paper_size || document_design.paper_size
    end

    # Generate preview: PDF → JPG + overlay data
    # Returns { success:, jpg_path:, overlay_data:, page_width:, page_height:, error: }
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

      db_path = File.join(work, "preview.db")
      pdf_path = File.join(work, "preview.pdf")
      work_jpg = File.join(work, "preview.jpg")

      db_doc = nil
      overlay_data = nil
      begin
        # The DB build, PDF render, and overlay read all go through doc_processor's
        # global Sequel models, so they must run one-at-a-time per process.
        GENERATION_LOCK.synchronize do
          # 1. Create and populate SQLite database
          db_doc = create_db_document(db_path)
          populate_database(db_doc)

          # 2. Generate PDF via doc_processor_rb renderer
          generate_pdf(db_doc, pdf_path)

          # 3. Extract overlay data from block_overlays table
          overlay_data = extract_overlay_data(db_doc)

          # 4. Synthesize heading overlay for TOC (the renderer only emits toc_entry overlays)
          if document_design.doc_type == "toc" && document_design.heading_height_in_lines.to_i > 0
            overlay_data = synthesize_toc_heading_overlay + overlay_data
          end
        ensure
          db_doc&.close # release the connection before the next thread rebinds the models
          db_doc = nil
        end

        # 5. Convert PDF → JPG (libvips, no Sequel models — safe outside the lock)
        convert_pdf_to_jpg(pdf_path, work_jpg)

        # 6. Publish: rename the finished JPG into place (atomic, same FS), then the
        # stamp that validates it. Concurrent runs produce equivalent output, so
        # last-writer-wins is safe.
        File.rename(work_jpg, jpg_path)
        save_cache_stamp(overlay_data)

        {
          success: true,
          jpg_path: jpg_path,
          overlay_data: overlay_data,
          page_width: paper_size.width_pt,
          page_height: paper_size.height_pt,
          error: nil
        }
      rescue => e
        Rails.logger.error "DesignPreviewService error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        {
          success: false,
          jpg_path: nil,
          overlay_data: [],
          page_width: paper_size.width_pt,
          page_height: paper_size.height_pt,
          error: e.message
        }
      ensure
        db_doc&.close
        FileUtils.rm_rf(work)
      end
    end

    # Path where the JPG preview lives (for serving from controller)
    def jpg_path
      File.join(preview_dir, "preview.jpg")
    end

    def clear_cache
      FileUtils.rm_rf(preview_dir)
    end

    private

    def preview_dir
      Rails.root.join("tmp", "previews", "dd_#{document_design.id}")
    end

    # Private per-call working dir (unique per generation) so concurrent renders of
    # the same document never share a SQLite DB. Under tmp/previews so the published
    # JPG rename stays on a single filesystem (atomic).
    def work_dir
      Rails.root.join("tmp", "previews", ".work", "dd_#{document_design.id}_#{SecureRandom.hex(8)}")
    end

    def cache_fingerprint
      timestamps = [
        document_design.updated_at,
        paper_size.updated_at,
        paper_size.theme.updated_at,
        document_design.paragraph_styles.maximum(:updated_at),
        document_design.heading_elements.maximum(:updated_at),
        paper_size.theme.base_paragraph_styles.maximum(:updated_at)
      ].compact
      Digest::MD5.hexdigest(timestamps.map(&:to_s).join("-"))
    end

    def cache_stamp_path
      File.join(preview_dir, "cache_stamp.json")
    end

    def load_cached_preview
      stamp_path = cache_stamp_path
      jpg = File.join(preview_dir, "preview.jpg")
      return nil unless File.exist?(stamp_path) && File.exist?(jpg)

      stamp = JSON.parse(File.read(stamp_path))
      return nil unless stamp["fingerprint"] == cache_fingerprint

      {
        success: true,
        jpg_path: jpg,
        overlay_data: stamp["overlay_data"].map(&:symbolize_keys),
        page_width: paper_size.width_pt,
        page_height: paper_size.height_pt,
        error: nil
      }
    rescue JSON::ParserError
      nil
    end

    def save_cache_stamp(overlay_data)
      File.write(cache_stamp_path, {
        fingerprint: cache_fingerprint,
        overlay_data: overlay_data
      }.to_json)
    end

    def create_db_document(db_path)
      File.delete(db_path) if File.exist?(db_path)
      DocProcessorRb::Database::DBDocument.new(path: db_path, create_if_needed: true)
    end

    def populate_database(db_doc)
      populate_document(db_doc)
      populate_master_page(db_doc)
      populate_heading_items(db_doc)
      populate_paragraph_styles(db_doc)
      populate_toc_items(db_doc)
      populate_sample_blocks(db_doc)
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
        page_width: ps.width_pt,
        page_height: ps.height_pt,
        margin_top: ps.top_margin_pt,
        margin_bottom: ps.bottom_margin_pt,
        margin_left: ps.left_margin_pt,
        margin_right: ps.right_margin_pt,
        binding_margin: ps.binding_margin_pt,
        paper_size: ps.size_name,
        body_font: theme.base_body_font,
        body_font_size: theme.base_body_font_size,
        body_line_height: ps.body_line_height,
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
        width: ps.width_pt,
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
            line_height: paper_size.body_line_height,
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

      repeat = document_design.doc_type == "copyright" ? 1 : (doc_type.single_page? ? 2 : 6)
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
      component_class = doc_layout_class
      component = component_class.new(
        db_document: db_doc,
        doc_info: doc_info,
        svg: true
      )

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

      doc = HexaPDF::Document.open(pdf_path)
      page = doc.pages[0]
      contents_ref = page[:Contents]

      existing_stream = if contents_ref.is_a?(Array)
        contents_ref.map { |ref| ref.stream }.join("\n")
      else
        contents_ref.stream
      end

      # Insert page bg BEFORE text commands but AFTER any white fill from the component
      c, m, y, k = color.map { |v| v / 100.0 }
      bg_commands = "q\n"
      bg_commands += "#{c} #{m} #{y} #{k} k\n"
      bg_commands += "#{-BLEED_PT} #{-BLEED_PT} #{ps.width_pt + 2 * BLEED_PT} #{ps.height_pt + 2 * BLEED_PT} re\n"
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
        line_height: style.text_line_spacing&.to_f || paper_size.body_line_height,
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
      line_height = paper_size.body_line_height
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

    def convert_pdf_to_jpg(pdf_path, jpg_path)
      Design::PdfToJpg.convert(pdf_path, jpg_path, dpi: PREVIEW_DPI)
    end

    def synthesize_toc_heading_overlay
      ps = paper_size
      dd = document_design
      heading_h = dd.heading_height_in_lines * ps.body_line_height

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

    def extract_overlay_data(db_doc)
      overlays = db_doc.block_overlays(document_id: 1, page_number: 1)
      overlays.map do |o|
        {
          type: o.overlay_type,
          x: o.rendered_x.to_f,
          y: o.rendered_y.to_f,
          width: o.rendered_width.to_f,
          height: o.rendered_height.to_f,
          markup: o.markup,
          content_preview: o.content_preview,
          is_continuation: o.is_continuation == 1
        }
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
  end
end
