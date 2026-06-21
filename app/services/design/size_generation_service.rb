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

      default_chapter_styles = default_chapter_dd.paragraph_styles.index_by(&:name)
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

        # Generate proportional paragraph styles
        default_chapter_styles.each do |name, default_style|
          target_style = target_chapter_dd.paragraph_styles.find_or_initialize_by(name: name)

          # Copy all attributes from default
          copy_style_attrs(target_style, default_style)

          # Apply proportional rules based on style category
          if HEADING_STYLES.include?(name)
            # Heading: font size proportional to height
            target_style.font_size = (default_style.font_size * ratio_h).round(2) if default_style.font_size
          elsif BODY_SUBHEADING_STYLES.include?(name)
            # Sub-headings: font size proportional to body_line_count ratio
            target_style.font_size = (default_style.font_size * line_count_ratio).round(2) if default_style.font_size
          elsif BODY_STYLES.include?(name)
            # Body: font size stays SAME
            target_style.font_size = default_style.font_size
          else
            # Other (caption, footnote, toc_*, cover_*): proportional to height
            target_style.font_size = (default_style.font_size * ratio_h).round(2) if default_style.font_size
          end

          # Spacing values proportional to height ratio
          SPACING_ATTRS.each do |attr|
            val = default_style.send(attr)
            target_style.send("#{attr}=", (val * ratio_h).round(2)) if val && val > 0
          end

          target_style.save!
        end

        # Copy other doc type designs from default (they inherit from chapter via Part 1)
        default_ps.document_designs.where.not(doc_type: "chapter").each do |default_dd|
          target_dd = target_ps.document_designs.find_or_create_by!(doc_type: default_dd.doc_type) do |dd|
            copy_document_design_attrs(dd, default_dd)
          end

          # Copy doc-type-specific style overrides
          default_dd.paragraph_styles.each do |default_style|
            target_style = target_dd.paragraph_styles.find_or_initialize_by(name: default_style.name)
            copy_style_attrs(target_style, default_style)

            # Apply same proportional rules
            if default_style.font_size
              if HEADING_STYLES.include?(default_style.name)
                target_style.font_size = (default_style.font_size * ratio_h).round(2)
              elsif BODY_SUBHEADING_STYLES.include?(default_style.name)
                target_style.font_size = (default_style.font_size * line_count_ratio).round(2)
              elsif !BODY_STYLES.include?(default_style.name)
                target_style.font_size = (default_style.font_size * ratio_h).round(2)
              end
            end

            SPACING_ATTRS.each do |attr|
              val = default_style.send(attr)
              target_style.send("#{attr}=", (val * ratio_h).round(2)) if val && val > 0
            end

            target_style.save!
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

    COPYABLE_STYLE_ATTRS = %i[
      korean_name font font_size text_color text_align tracking space_width scale
      first_line_indent text_line_spacing space_before space_after
      space_before_in_lines space_after_in_lines left_indent right_indent
      bold_font bold_text_color emphasis_color emphasis_font
      fill_type fill_color fill_ending_color fill_gradient_direction
      border_thickness border_color border_side rounded_corners corner_radius
      padding_top padding_bottom
    ].freeze

    def copy_style_attrs(target, source)
      COPYABLE_STYLE_ATTRS.each do |attr|
        target.send("#{attr}=", source.send(attr))
      end
    end
  end
end
