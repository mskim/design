module Design
  class SizeGenerationService
    # Auto-generate proportional styles for other paper sizes from the default (first) paper size.
    #
    # Rules:
    # - Margins: proportional to paper dimensions
    # - Body font size: SAME across all sizes
    # - body_line_count: calculated from content height and body line height
    # - Heading elements (title, subtitle, author, publisher, quote): font size proportional to height
    # - Body sub-headings (h2-h6): font size proportional to body_line_count ratio
    # - Spacing values: proportional to height ratio
    # - Values are read from the default chapter's RESOLVED styles (theme base →
    #   chapter). Target chapter rows store only fields that differ from the theme
    #   base; other doc types copy only the default size's own non-nil fields.
    #
    # Usage:
    #   Design::SizeGenerationService.new(theme).generate!

    HEADING_STYLES = %w[title subtitle author publisher quote].freeze
    BODY_SUBHEADING_STYLES = %w[h2 h3 h4 h5 h6].freeze
    BODY_STYLES = %w[body].freeze
    SPACING_ATTRS = %i[space_before space_after first_line_indent left_indent right_indent
                       text_line_spacing padding_top padding_bottom].freeze

    def initialize(theme)
      @theme = theme
    end

    def generate!
      default_ps = @theme.default_paper_size
      raise "No default paper size found" unless default_ps

      default_chapter_dd = default_ps.document_designs.find_by(doc_type: "chapter")
      raise "No chapter document design on default paper size" unless default_chapter_dd

      # Resolved (theme base → chapter) so a sparse chapter row still yields its
      # inherited values (e.g. body font_size from the theme).
      default_chapter_styles = default_chapter_dd.merged_paragraph_styles.index_by(&:name)
      base_styles = @theme.base_paragraph_styles.index_by(&:name)
      default_body_style = default_chapter_styles["body"]
      default_body_line_count = default_ps.body_line_count

      @theme.paper_sizes.where.not(id: default_ps.id).each do |target_ps|
        ratio_w = target_ps.width_mm / default_ps.width_mm
        ratio_h = target_ps.height_mm / default_ps.height_mm

        # Update margins proportionally
        target_ps.update!(
          left_margin_mm: (default_ps.left_margin_mm * ratio_w).round(2),
          top_margin_mm: (default_ps.top_margin_mm * ratio_h).round(2),
          right_margin_mm: (default_ps.right_margin_mm * ratio_w).round(2),
          bottom_margin_mm: (default_ps.bottom_margin_mm * ratio_h).round(2),
          binding_margin_mm: (default_ps.binding_margin_mm * ratio_w).round(2)
        )

        # Calculate body_line_count from content height
        if default_body_style&.font_size
          default_body_line_height = default_ps.content_height_pt / default_body_line_count
          target_content_height = target_ps.content_height_pt
          target_body_line_count = (target_content_height / default_body_line_height).floor
          target_ps.update!(body_line_count: [target_body_line_count, 10].max)
        end

        target_body_line_count = target_ps.body_line_count
        line_count_ratio = default_body_line_count.to_f / target_body_line_count

        # Generate chapter styles for this paper size
        target_chapter_dd = target_ps.document_designs.find_or_create_by!(doc_type: "chapter") do |dd|
          copy_document_design_attrs(dd, default_chapter_dd)
        end

        # Copy/update heading elements
        target_chapter_dd.heading_elements.destroy_all
        default_chapter_dd.heading_elements.each do |he|
          target_chapter_dd.heading_elements.create!(
            element_type: he.element_type,
            style_name: he.style_name,
            position: he.position
          )
        end

        # Chapter: scale every resolved style, then store only the fields that
        # differ from the theme base (the rest inherit).
        default_chapter_styles.each do |name, default_style|
          values = scaled_values(name, default_style, ratio_h, line_count_ratio)
          base = base_styles[name]
          sparse = values.to_h do |f, v|
            [ f, base && ParagraphStyle.same_value?(f, v, base[f]) ? nil : v ]
          end
          write_sparse_row(target_chapter_dd, name, sparse, has_parent: base.present?,
                           korean_name: default_style.korean_name)
        end

        # Other doc types: copy only the default size's own (non-nil) fields,
        # scaled by the same rules; everything else inherits through chapter.
        default_ps.document_designs.where.not(doc_type: "chapter").each do |default_dd|
          target_dd = target_ps.document_designs.find_or_create_by!(doc_type: default_dd.doc_type) do |dd|
            copy_document_design_attrs(dd, default_dd)
          end

          default_dd.paragraph_styles.each do |default_style|
            values = scaled_values(default_style.name, default_style, ratio_h, line_count_ratio)
            write_sparse_row(target_dd, default_style.name, values,
                             has_parent: target_dd.style_has_parent?(default_style.name),
                             korean_name: default_style.korean_name)
          end
        end
      end

      # Re-export the theme DB
      ThemeDbExportService.new(@theme).export!
    end

    private

    def copy_document_design_attrs(target, source)
      target.heading_height_in_lines = source.heading_height_in_lines
      target.heading_v_align = source.heading_v_align
      target.column_count = source.column_count
      target.gutter = source.gutter
      target.has_header = source.has_header
      target.has_footer = source.has_footer
      target.header_left_content_string = source.header_left_content_string
      target.header_right_content_string = source.header_right_content_string
      target.footer_left_content_string = source.footer_left_content_string
      target.footer_right_content_string = source.footer_right_content_string
      target.show_header_footer_on_first_page = source.show_header_footer_on_first_page
    end

    # STYLE_FIELDS of `style` with font_size and spacing scaled for the target
    # size: headings and "other" styles by height, h2–h6 by the body_line_count
    # ratio, body unchanged; spacing (when > 0) by height.
    def scaled_values(name, style, ratio_h, line_count_ratio)
      values = ParagraphStyle::STYLE_FIELDS.index_with { |f| style[f] }
      if (size = values["font_size"])
        values["font_size"] =
          if BODY_STYLES.include?(name) then size
          elsif BODY_SUBHEADING_STYLES.include?(name) then (size * line_count_ratio).round(2)
          else (size * ratio_h).round(2) # HEADING_STYLES and other styles
          end
      end
      SPACING_ATTRS.each do |attr|
        val = values[attr.to_s]
        values[attr.to_s] = (val * ratio_h).round(2) if val && val > 0
      end
      values
    end

    # Write `values` (STYLE_FIELD => value or nil) as `name`'s row on `dd`. A row
    # left all-nil is removed (not created) when the style inherits from a parent;
    # a parentless style keeps its row so the style still exists on this size.
    def write_sparse_row(dd, name, values, has_parent:, korean_name: nil)
      row = dd.paragraph_styles.find_by(name: name)
      if has_parent && values.values.all?(&:nil?)
        row&.destroy!
        return
      end
      row ||= dd.paragraph_styles.build(name: name)
      row.assign_attributes(values)
      row.korean_name ||= korean_name unless has_parent
      row.overridden_fields = Array(row.overridden_fields) & values.compact.keys
      row.save!
    end
  end
end
