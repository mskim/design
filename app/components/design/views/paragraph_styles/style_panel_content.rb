module Design
  module Views
    module ParagraphStyles
      # The re-rendered part of the style panel (#style-panel-content): header
      # (chip, ▾ menu, scope, names) and the field sections. Drawn entirely from
      # DocumentDesign#style_state for THIS paper size: inherited fields show the
      # doc type's parent (theme for chapter; chapter's resolved style for the
      # rest); the dot and × follow this size's changed fields, push eligibility
      # this size's user-marked fields.
      class StylePanelContent < Design::Views::Base
        include Design::Views::FieldGroups
        include BorderSection

        # Panel order; together exactly ParagraphStyle::STYLE_FIELDS (tested).
        SECTIONS = {
          "type_text" => %w[font font_size scale text_color text_align tracking space_width text_line_spacing],
          "bold"      => %w[bold_font emphasis_font bold_text_color emphasis_color],
          "space"     => %w[first_line_indent left_indent right_indent space_before space_after
                            space_before_in_lines space_after_in_lines],
          "fill"      => %w[fill_type fill_gradient_direction fill_color fill_ending_color],
          "border"    => %w[border_top_thickness border_top_color border_right_thickness border_right_color
                            border_bottom_thickness border_bottom_color border_left_thickness border_left_color
                            corner_top_left corner_top_right corner_bottom_left corner_bottom_right],
          "pad"       => %w[padding_top padding_bottom]
        }.freeze
        ALWAYS_OPEN = "type_text"

        # field → [kind, design.fields.* label key, options]
        FIELDS = {
          "font"                    => [ :font, "font" ],
          "font_size"               => [ :number, "size", { step: 0.1, min: 0 } ],
          "scale"                   => [ :number, "scale", { step: 1.0, min: 0, unit: :percent } ],
          "text_color"              => [ :color, "color", { span: true } ],
          "text_align"              => [ :select, "align", { options: Design::ParagraphStyle::TEXT_ALIGNS, i18n: "text_align" } ],
          "tracking"                => [ :number, "tracking", { step: 0.1, unit: :none } ],
          "space_width"             => [ :number, "space_width", { step: 0.1, unit: :none } ],
          "text_line_spacing"       => [ :number, "line_spacing", { step: 0.1, min: 0 } ],
          "bold_font"               => [ :font, "bold_font" ],
          "emphasis_font"           => [ :font, "emphasis_font" ],
          "bold_text_color"         => [ :color, "bold_color" ],
          "emphasis_color"          => [ :color, "emphasis_color" ],
          "first_line_indent"       => [ :number, "first_line_indent", { step: 0.1 } ],
          "left_indent"             => [ :number, "left_indent", { step: 0.1 } ],
          "right_indent"            => [ :number, "right_indent", { step: 0.1 } ],
          "space_before"            => [ :number, "space_before_pt", { step: 0.1, min: 0 } ],
          "space_after"             => [ :number, "space_after_pt", { step: 0.1, min: 0 } ],
          "space_before_in_lines"   => [ :number, "space_before_lines", { step: 0.1, min: 0, unit: :lines } ],
          "space_after_in_lines"    => [ :number, "space_after_lines", { step: 0.1, min: 0, unit: :lines } ],
          "fill_type"               => [ :select, "fill_type", { options: Design::ParagraphStyle::FILL_TYPES, i18n: "fill_type" } ],
          "fill_gradient_direction" => [ :select, "gradient_dir",
                                         { options: Design::ParagraphStyle::GRADIENT_DIRECTIONS, i18n: "gradient_dir" } ],
          "fill_color"              => [ :color, "fill_color" ],
          "fill_ending_color"       => [ :color, "ending_color" ],
          **Design::ParagraphStyle::SIDES.flat_map { |s|
            [ [ "border_#{s}_thickness", [ :number, "border_#{s}_thickness", { step: 0.1, min: 0 } ] ],
              [ "border_#{s}_color", [ :color, "border_#{s}_color" ] ] ]
          }.to_h,
          **Design::ParagraphStyle::CORNERS.to_h { |c|
            [ "corner_#{c}", [ :select, "corner_#{c}", { options: Design::ParagraphStyle::CORNER_SIZES, i18n: "corner_size" } ] ]
          },
          "padding_top"             => [ :number, "padding_top", { step: 0.1, min: 0 } ],
          "padding_bottom"          => [ :number, "padding_bottom", { step: 0.1, min: 0 } ]
        }.freeze

        def self.field_label(field) = I18n.t("design.fields.#{FIELDS.fetch(field)[1]}")

        # field_errors: { field => [messages] }, attempted: { field => value } (a
        # 422 re-render keeps what the user typed); error: a panel-level message.
        def initialize(document_design:, style_name:, editable: true, field_errors: {}, attempted: {}, error: nil)
          @design = document_design
          @name = style_name
          @editable = editable
          @field_errors = field_errors.to_h.transform_keys(&:to_s)
          @attempted = attempted.to_h.transform_keys(&:to_s)
          @error = error
          @state = document_design.style_state(style_name)
        end

        def view_template
          div(id: "style-panel-content", class: "flex flex-col gap-3") do
            header
            div(class: "rounded border border-red-300 bg-red-50 p-2 text-sm text-red-800", role: "alert") { @error } if @error
            SECTIONS.each { |key, fields| section(key, fields) }
          end
        end

        private

        def changed = @state[:changed_fields]
        def user_fields = @state[:user_fields]
        def parent = @state[:parent_values]
        def own = @state[:own]
        def chapter? = @design.doc_type == "chapter"

        # 되돌리기 reverts every size, so it counts the union of the fields
        # changed on any size of this doc type (not a per-size total).
        def changed_on_all_sizes = @changed_on_all_sizes ||= @design.style_changed_fields_on_all_sizes(@name)

        def field_state(f)
          return :inherited unless changed.include?(f)
          user_fields.include?(f) ? :changed : :generated
        end

        # ── header ──

        def header
          div(class: "flex flex-col gap-1") do
            div(class: "flex items-center gap-1.5") do
              chip
              menu
            end
            p(class: "text-xs text-slate-500", data: { scope: true }) do
              "#{doc_type_label(@design.doc_type)} · #{I18n.t('design.style_panel.all_sizes')}"
            end
            names
          end
        end

        def chip
          span(class: "inline-flex items-center gap-0.5 rounded-full bg-slate-200 px-2.5 py-0.5 text-sm font-semibold text-slate-900",
               data: { style_chip: true }) do
            plain @name
            if changed.any?
              span(class: "text-blue-600", title: I18n.t("design.style_panel.has_changes"), data: { changed_marker: true }) { "+" }
            end
          end
        end

        def menu
          div(class: "relative", data: { controller: "design--dropdown" }) do
            button(type: "button", class: "rounded px-1.5 py-0.5 text-sm text-slate-600 hover:bg-slate-200 disabled:opacity-50",
                   aria: { haspopup: "menu", label: I18n.t("design.style_panel.menu") },
                   disabled: (true unless @editable), data: { action: "design--dropdown#toggle" }) { "▾" }
            div(class: "hidden absolute left-0 z-20 mt-1 w-56 rounded-md border border-slate-200 bg-white py-1 shadow-lg",
                role: "menu", data: { "design--dropdown-target": "menu" }) do
              revert_count = changed_on_all_sizes.size
              revertable = revert_count.positive? && @state[:has_parent]
              menu_item(I18n.t("design.style_panel.revert_all", count: revert_count), "revertStyle",
                        disabled: !revertable,
                        confirm: (I18n.t("design.style_panel.revert_confirm", count: revert_count) if revertable))
              menu_item(I18n.t(chapter? ? "design.style_panel.push_to_theme" : "design.style_panel.push_to_chapter"),
                        "pushStyle", disabled: user_fields.empty?, confirm: push_confirm)
              menu_item(I18n.t("design.style_panel.all_options"), nil, disabled: true)
            end
          end
        end

        def menu_item(label, action, disabled:, confirm: nil)
          button(type: "button", role: "menuitem", disabled: (true if disabled),
                 class: "block w-full px-3 py-1.5 text-left text-sm text-slate-700 hover:bg-slate-100 disabled:text-slate-400 disabled:hover:bg-transparent",
                 data: { action: ("design--style-autosave##{action}" if action), confirm_message: confirm }) { label }
        end

        # What a push moves up, and — from push_preview — how many sibling doc
        # types keep their own value for each of those fields.
        def push_confirm
          return nil if user_fields.empty?
          lines = [ I18n.t("design.style_panel.push_confirm.#{chapter? ? 'theme' : 'chapter'}", count: user_fields.size) ]
          @design.push_preview(@name).each do |f, n|
            lines << I18n.t("design.style_panel.push_confirm.kept", field: self.class.field_label(f), count: n) if n.positive?
          end
          lines.join("\n")
        end

        def names
          dl(class: "grid grid-cols-[auto_1fr] gap-x-2 text-xs") do
            dt(class: "text-slate-500") { I18n.t("design.fields.name") }
            dd(class: "text-slate-900", data: { style_name: true }) { @name }
            dt(class: "text-slate-500") { I18n.t("design.fields.korean_name") }
            dd(class: "text-slate-900", data: { korean_name: true }) { korean_name.presence || "—" }
          end
        end

        def korean_name = @design.merged_paragraph_styles.find { |s| s.name == @name }&.korean_name

        # ── sections and fields ──

        def section(key, fields)
          has_change = fields.intersect?(changed)
          details(open: (key == ALWAYS_OPEN || has_change), data: { section: key },
                  class: "min-w-0 rounded-lg border #{GROUP_BOX_CLASS} px-3 pb-3 pt-1.5") do
            summary(class: "inline-flex cursor-pointer select-none items-center gap-1.5 rounded px-2 py-0.5 text-sm font-semibold #{GROUP_LEGEND_CLASS}") do
              plain I18n.t("design.style_panel.sections.#{key}")
              span(class: "h-1.5 w-1.5 rounded-full bg-blue-600", data: { section_dot: true }) if has_change
            end
            div(class: "mt-2") { key == "border" ? border_section_body : rows { fields.each { |f| field(f) } } }
          end
        end

        def field(f)
          kind, label_key, opts = FIELDS.fetch(f)
          opts ||= {}
          label = I18n.t("design.fields.#{label_key}")
          render StyleField.new(field: f, label: label, state: field_state(f), source: source_label,
                                parent_text: parent_text(f, kind, opts),
                                error: Array(@field_errors[f]).first, editable: @editable,
                                span: opts[:span] || kind == :font) do
            control(f, kind, label, opts)
          end
        end

        def control(f, kind, label, opts)
          name = "paragraph_style[#{f}]"
          disabled = !@editable
          case kind
          when :number
            render Design::Views::Inputs::NumberField.new(
              name: name, value: shown_value(f), placeholder: display(parent[f]), label: label,
              unit: opts.fetch(:unit, :pt), step: opts.fetch(:step, 0.1), min: opts[:min], disabled: disabled)
          when :color
            render Design::Views::Inputs::ColorField.new(
              name: name, value: shown_value(f).to_s, inherited_value: parent[f], label: label, disabled: disabled)
          when :select, :font
            id = Design::Views::Inputs::InheritSelect.default_id(name)
            field_row(label, for: id) do
              render Design::Views::Inputs::InheritSelect.new(
                name: name, id: id, value: shown_value(f), inherited_value: parent[f], i18n_scope: opts[:i18n],
                options: kind == :font ? Design::Theme::AVAILABLE_FONTS : opts.fetch(:options), disabled: disabled)
            end
          end
        end

        # A field's own value (nil when inherited → empty control); after a 422,
        # the value the user tried.
        def shown_value(f) = @attempted.key?(f) ? @attempted[f].to_s : display(own&.[](f))

        def display(value)
          case value
          when nil then nil
          when BigDecimal then value.to_s("F")
          else value.to_s
          end
        end

        # The inherited value as the tooltip reads it: option labels, colour
        # summaries and numbers with the control's unit.
        def parent_text(f, kind, opts)
          v = parent[f]
          return nil if v.nil?
          case kind
          when :select then opts[:options].include?(v) ? I18n.t("design.options.#{opts[:i18n]}.#{v}") : display(v)
          when :color then Design::Views::Inputs::ColorValue.summary(v)
          when :number then with_unit(display(v), opts.fetch(:unit, :pt))
          else display(v)
          end
        end

        def with_unit(text, unit)
          suffix = Design::Views::Inputs::NumberField.suffix_for(unit)
          return text unless suffix
          unit == :lines ? "#{text} #{suffix}" : "#{text}#{suffix}"
        end

        def source_label = I18n.t(chapter? ? "design.style_panel.from_theme" : "design.style_panel.from_chapter")
      end
    end
  end
end
