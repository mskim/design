module Design
  module BookDesignFile
    # A DesignCraft document's paragraph styles read back as the app's (Design::ParagraphStyle
    # fields): the reverse of designcraft_rb's DocProcessor::Styles.paragraph. Family and
    # style → the font's name (its file's, when the book fonts are at hand), italic (the
    # engine's italic, or an "… Italic" face) → font_style "italic" and the upright face's
    # name, size, align, indents, space before/after → whole lines of the body's leading,
    # tracking (thousandths of an em → points) and the fill's swatch → a colour.
    #
    # A document.json style holds only what it sets, plus basedOn: a style resolves its chain
    # (it, its basedOn, …, the root), each key from the first style that sets it, as
    # TemplateCraft::Styles resolves them.
    class Styles
      ROOT = "[No Paragraph Style]"
      COMPOSITE_PREFIX = "CompositeFont/"
      ALIGN = { "left" => "left", "center" => "center", "right" => "right", "justify" => "justify",
                "leftJustified" => "justify", "centerJustified" => "justify", "rightJustified" => "justify",
                "fullyJustified" => "justify" }.freeze
      # designcraft_rb's DocProcessor::Styles::FONT_FAMILIES, file name → family.
      FONT_FAMILIES = { "NotoSerifKR" => "Noto Serif KR", "NotoSansKR" => "Noto Sans KR", "Courier" => "Courier New" }.freeze
      # Fonts named with their style even when it's Regular ("NotoSerifKR-Regular").
      STYLED = %w[NotoSerifKR NotoSansKR].freeze

      # font_dir: the book fonts (DesignCraftRb.font_dir), whose files name the fonts.
      def initialize(document, font_dir: nil)
        @styles = Array(document.dig("styles", "paragraph")).to_h { [ it["name"], it ] }
        @swatches = Array(document["swatches"]).to_h { [ it["name"], it ] }
        @faces = font_files(font_dir).to_h { |file, face| [ face, file ] }
      end

      def names = @styles.keys

      def include?(name) = @styles.key?(name)

      # {"para" =>, "chars" =>} of the style's chain merged, or nil for a style it hasn't.
      def resolve(name)
        style = @styles[name] or return
        chain = chain(style).reverse
        { "para" => chain.map { it.fetch("para", {}) }.reduce({}, :merge),
          "chars" => chain.map { it.fetch("chars", {}) }.reduce({}, :merge) }
      end

      # The style's leading in points, or nil (auto, or none).
      def leading(name)
        value = resolve(name)&.dig("chars", "leading")
        value = value["value"] if value.is_a?(Hash) && value["kind"] == "points"
        value if value.is_a?(Numeric) && value.positive?
      end

      # Design::ParagraphStyle attributes for the style: line_height is the body's leading
      # (the grid its spaces are whole lines of).
      def attributes(name, line_height:)
        resolved = resolve(name) or return
        para, chars = resolved.values_at("para", "chars")
        size = number(chars["size"])
        italic = chars["italic"] == true || chars["fontStyle"].to_s.end_with?("Italic")
        {
          font: font_name(chars["fontFamily"], upright(chars["fontStyle"])),
          font_style: ("italic" if italic),
          font_size: size,
          text_align: ALIGN[para["align"].to_s],
          text_color: color(chars["fill"]),
          tracking: (tracking(chars["tracking"], size) if chars.key?("tracking")),
          first_line_indent: number(para["firstLineIndent"]),
          left_indent: number(para["leftIndent"]),
          right_indent: number(para["rightIndent"]),
          text_line_spacing: line_spacing(leading(name), size, line_height),
          **space(:before, para["spaceBefore"], line_height),
          **space(:after, para["spaceAfter"], line_height)
        }
      end

      # "Noto Serif KR" + "Bold" → "NotoSerifKR-Bold"; a book font by its file's name
      # ("smShinShinMyungjoP" + "W30" → "smShinShinMyungjoP-30").
      def font_name(family, style)
        return if family.blank?

        family = family.delete_prefix(COMPOSITE_PREFIX)
        style = style.presence || "Regular"
        @faces[[ family, style ]] || begin
          base = FONT_FAMILIES.key(family) || family.delete(" ")
          style == "Regular" && !STYLED.include?(base) ? base : "#{base}-#{style}"
        end
      end

      # A swatch's colour as the app writes it ("CMYK=0,0,0,80", "#cc3300"); nil for none
      # or black, the default.
      def color(swatch_name)
        color = @swatches.dig(swatch_name.to_s, "value", "color") or return
        case color["model"]
        when "cmyk"
          values = %w[c m y k].map { ((color[it] || 0) * 100).round(1) }
          values == [ 0, 0, 0, 100 ] ? nil : "CMYK=#{values.map { it == it.to_i ? it.to_i : it }.join(',')}"
        when "rgb"
          hex = format("#%02x%02x%02x", *%w[r g b].map { ((color[it] || 0) * 255).round.clamp(0, 255) })
          hex == "#000000" ? nil : hex
        end
      end

      private

      def chain(style)
        seen = []
        while style && !seen.include?(style)
          seen << style
          style = @styles[style["basedOn"]] || (@styles[ROOT] unless style["name"] == ROOT)
        end
        seen
      end

      # "Bold Italic" → "Bold", "Italic" → nil (Regular), as designcraft_rb's Italic.upright.
      def upright(style) = style.to_s.sub(/\s*Italic\z/, "").presence

      def number(value) = (value.to_f.round(3) if value.is_a?(Numeric))

      def tracking(value, size) = (size && (value.to_f * size / 1000).round(2))

      # The leading over the size (행간), only where it isn't the body grid's.
      def line_spacing(leading, size, line_height)
        return unless leading && size
        return if line_height && (leading - line_height).abs < 0.01

        (leading - size).round(3)
      end

      # Whole lines of the grid (DesignCraft sets spaces in whole lines; a space a hair off
      # rounds to them).
      def space(side, value, line_height)
        return {} unless value.is_a?(Numeric) && line_height&.positive?

        { "space_#{side}_in_lines": (value / line_height).round }
      end

      def font_files(dir)
        return {} unless dir

        require "designcraft_rb"
        DesignCraftRb::DocProcessor::Styles.font_files(dir)
      rescue LoadError
        {}
      end
    end
  end
end
