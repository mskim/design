module Design
  module GenerationRules
    module_function

    # All rules interpolate between two reference paper sizes (the live Seoul theme):
    #   신국판 (sin-gukpan) = 152×225 mm  — the smaller anchor
    #   A4                  = 210×297 mm  — the larger anchor
    # t_h is the 0..1 (extrapolating beyond) position by height between them.
    SIN_H  = 225.0           # 신국판 height (smaller anchor)
    H_SPAN = 297.0 - 225.0   # A4 − 신국판 height span = 72.0

    MARGIN_RATIOS = {
      left:    22.0 / 152.0, right: 22.0 / 152.0,
      top:     18.0 / 225.0, bottom: 28.0 / 225.0,
      binding: 3.0  / 152.0
    }.freeze

    FLOORS = { margin: 5.0, binding: 1.0, body_line_count: 8, heading: 6.0 }.freeze

    COVER   = %w[cover_title cover_subtitle cover_author cover_publisher cover_body].freeze
    SENECA  = %w[seneca_title seneca_author seneca_publisher].freeze
    WING    = %w[wing_title wing_body].freeze
    HEADING = %w[title subtitle author h2 h3 h4 h5 h6].freeze
    BODY    = %w[body blockquote quote footnote caption caption_title image_caption ol ul source].freeze
    RUNNING = %w[header_left header_right footer_left footer_right].freeze
    TABLE   = %w[table_heading_cell table_body_cell].freeze
    FAMILY_NAMES = (COVER + SENECA + WING + HEADING + BODY + RUNNING + TABLE).uniq.freeze

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
      [ (23 + 17 * t_h(height_mm)).round, FLOORS[:body_line_count] ].max  # blc: 신국판 23 → A4 40 (two-anchor)
    end

    def heading_scale_for(height_mm) = 0.75 + 0.25 * t_h(height_mm)  # heading scale: 신국판 ×0.75 → A4 ×1.0

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
