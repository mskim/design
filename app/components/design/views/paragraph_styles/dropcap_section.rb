module Design
  module Views
    module ParagraphStyles
      # The 드롭 캡 section's body in the style panel (drop cap plan, Task 7),
      # rendered only for the body style. Included in StylePanelContent: it uses
      # that class's `field_state`, `parent`, `own`, `rows`, `field_row` and its
      # @field_errors / @attempted / @editable.
      #
      # `dropcap` is one field holding a hash, so its row (a StyleField: dot, ×,
      # error) holds one box of value[...] controls ([data-hash-field]); any
      # committed change there saves the whole hash in one request
      # (design--style-autosave#hashChanged, field_save_jobs.js hashJobs). The
      # checkboxes have hidden "0" fallbacks, read like a form submission.
      # On sends the parts (they show DROPCAP_DEFAULT while off); off sends
      # value[enabled]=false when the parent — the theme base, whatever the doc
      # type (CHAPTER_LOCAL_FIELDS) — has a cap (data-parent-on), else reverts.
      module DropcapSection
        PREFIX = "value"
        CHECKBOXES = %w[align_left_edge scale_descenders].freeze

        private

        def dropcap_section_body
          render StyleField.new(field: "dropcap", label: dropcap_t("title"), state: field_state("dropcap"),
                                source: I18n.t("design.style_panel.from_theme"), parent_text: dropcap_parent_text,
                                error: Array(@field_errors["dropcap"]).first, editable: @editable, span: true) do
            div(class: "flex flex-col gap-2", data: { group: "dropcap", hash_field: "dropcap", parent_on: cap_on?(parent_cap).to_s }) do
              dropcap_checkbox("enabled", dropcap_on?, dropcap_t("enabled"), disabled: !@editable)
              rows do
                dropcap_number("lines", Design::ParagraphStyle::DROPCAP_LINES)
                dropcap_number("chars", Design::ParagraphStyle::DROPCAP_CHARS)
                dropcap_font
                div(class: "col-span-2") do
                  render Design::Views::Inputs::ColorField.new(
                    name: dropcap_name("color"), value: dropcap_values["color"].to_s, label: dropcap_t("color"),
                    empty_label: dropcap_t("same_as_body"), disabled: parts_disabled?)
                end
              end
              CHECKBOXES.each { |k| dropcap_checkbox(k, dropcap_values[k], dropcap_t(k), disabled: parts_disabled?) }
            end
          end
        end

        def dropcap_name(key) = "#{PREFIX}[#{key}]"
        def dropcap_t(key, **opts) = I18n.t("design.dropcap.#{key}", **opts)

        def dropcap_number(key, range)
          render Design::Views::Inputs::NumberField.new(
            name: dropcap_name(key), value: dropcap_values[key].to_s, label: dropcap_t(key),
            unit: :none, step: 1, min: range.min, max: range.max, disabled: parts_disabled?)
        end

        def dropcap_font
          name = dropcap_name("font")
          id = Design::Views::Inputs::InheritSelect.default_id(name)
          field_row(dropcap_t("font"), span: true, for: id) do
            render Design::Views::Inputs::InheritSelect.new(
              name: name, id: id, value: dropcap_values["font"], options: Design::Theme::AVAILABLE_FONTS,
              inherit_label: dropcap_t("same_as_body"), disabled: parts_disabled?)
          end
        end

        def dropcap_checkbox(key, checked, label_text, disabled:)
          label(class: "flex items-center gap-2 text-sm text-slate-700") do
            # Enabled even while its checkbox is off: hashValues reads every part on purpose.
            input(type: "hidden", name: dropcap_name(key), value: "0", disabled: (true unless @editable))
            input(type: "checkbox", name: dropcap_name(key), value: "1", checked: (true if checked),
                  class: "rounded border-slate-300", disabled: (true if disabled))
            plain label_text
          end
        end

        def parts_disabled? = !@editable || !dropcap_on?

        # What the controls show: the attempted value after a 422, else this doc
        # type's own cap, else the inherited one.
        def shown_cap
          return @shown_cap if defined?(@shown_cap)
          @shown_cap =
            if @attempted.key?("dropcap") then Design::ParagraphStyle.normalize_dropcap(@attempted["dropcap"])
            else Design::ParagraphStyle.normalize_dropcap(own&.dropcap) || parent_cap
            end
        end

        def parent_cap = @parent_cap ||= Design::ParagraphStyle.normalize_dropcap(parent["dropcap"])
        def cap_on?(cap) = !cap.nil? && cap != Design::ParagraphStyle::DROPCAP_OFF
        def dropcap_on? = cap_on?(shown_cap)

        # Off, the parts show what switching on would send: the parent's cap or the defaults.
        def dropcap_values
          @dropcap_values ||= begin
            cap = dropcap_on? ? shown_cap : (cap_on?(parent_cap) ? parent_cap : {})
            Design::ParagraphStyle::DROPCAP_DEFAULT.merge(cap)
          end
        end

        def dropcap_parent_text
          return nil if parent_cap.nil?
          return dropcap_t("disabled") unless cap_on?(parent_cap)
          cap = Design::ParagraphStyle::DROPCAP_DEFAULT.merge(parent_cap)
          dropcap_t("summary", lines: cap["lines"], chars: cap["chars"])
        end
      end
    end
  end
end
