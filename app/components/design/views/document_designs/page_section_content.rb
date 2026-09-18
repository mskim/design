module Design
  module Views
    module DocumentDesigns
      # The morphed part of the Page section (#page-section-content): 판형
      # (read-only + 판형 편집), 여백 (the paper size — every doc type on it),
      # 본문 (this design's body line count) and 단 (this design's columns).
      # Controls are named page[<field>] and belong to the empty
      # #page-section-form (form=), so the tabs form never sends them;
      # design--style-autosave on the enclosing PageSection saves each commit.
      #
      # Dot and × (StyleField): a margin when the user marked it AND it
      # differs from the rule — × returns it to the rule; body lines when this
      # design sets its own — × returns to the paper size's. Columns and gutter
      # have neither (emptying them is a 422 "필수").
      class PageSectionContent < Design::Views::Base
        include Design::Views::FieldGroups

        FORM_ID = "page-section-form"
        TARGET = "page-section-content"
        StyleField = Design::Views::ParagraphStyles::StyleField

        # field_errors: { field => [messages] }, attempted: { field => value }
        # (a 422 re-render keeps what the user typed).
        def initialize(document_design:, paper_size_url:, editable: true, field_errors: {}, attempted: {})
          @design = document_design
          @paper_size = document_design.paper_size
          @paper_size_url = paper_size_url
          @editable = editable
          @field_errors = field_errors.to_h.transform_keys(&:to_s)
          @attempted = attempted.to_h.transform_keys(&:to_s)
        end

        def view_template
          div(id: TARGET, class: "flex flex-col") do
            page_size_group
            margins_group
            body_group
            columns_group
          end
        end

        private

        def txt(key, **opts) = I18n.t("design.page_section.#{key}", **opts)

        # ── 판형 ──

        def page_size_group
          group_box("page_size", txt("page_size")) do
            div(class: "flex items-center justify-between gap-2 text-sm") do
              span(class: "text-slate-800", data: { page_size_summary: true }) do
                "#{size_label} #{mm(@paper_size.width_mm)} × #{mm(@paper_size.height_mm)} mm"
              end
              if @editable
                # Inside turbo-frame#properties_panel: leave the frame.
                a(href: @paper_size_url, data: { turbo_frame: "_top" },
                  class: "text-xs text-blue-600 hover:underline") { txt("edit_page_size") }
              end
            end
          end
        end

        def size_label = @paper_size.local_name.presence || @paper_size.size_name
        def mm(value) = value.to_d.round(1).to_s("F").delete_suffix(".0")

        # ── 여백 ──

        def margins_group
          group_box("margins", txt("margins")) do
            p(class: "mb-2 text-xs text-slate-500", data: { scope: true }) { txt("margin_scope", size: size_label) }
            div(class: "grid grid-cols-[1fr_auto_1fr] items-center gap-x-2 gap-y-2.5") do
              margin_field("top_margin_mm", "top")
              span
              margin_field("bottom_margin_mm", "bottom")
              margin_field("left_margin_mm", "left")
              link_toggle
              margin_field("right_margin_mm", "right")
              margin_field("binding_margin_mm", "binding")
            end
            p(class: "mt-1.5 text-xs text-slate-500", data: { binding_hint: true }) { txt("binding_hint") }
            warnings(@paper_size.margin_problems, "margins")
          end
        end

        def margin_field(f, label_key)
          label = txt(label_key)
          render StyleField.new(field: f, state: @paper_size.margin_changed?(f) ? :changed : :inherited, label: label,
                                error: error(f), editable: @editable, revert_label: txt("revert_margin", field: label)) do
            number(f, label: label, unit: :mm, step: 0.1, min: 0, value: shown(f, @paper_size[f]))
          end
        end

        # Pressed when Left = Right; afterwards client state (the autosave
        # controller keeps aria-pressed through morphs). The stable id lets a
        # morph match the button rather than recreate it, which would lose
        # the pressed state.
        def link_toggle
          button(id: "page-margin-link", type: "button", disabled: (true unless @editable), title: txt("link_left_right"),
                 class: "h-6 w-6 rounded text-sm leading-none text-slate-400 hover:bg-slate-200 aria-pressed:bg-slate-200 aria-pressed:text-slate-900 disabled:opacity-50",
                 aria: { pressed: (@paper_size.left_margin_mm == @paper_size.right_margin_mm).to_s, label: txt("link_left_right") },
                 data: { margin_link: true, action: "design--style-autosave#toggleLink" }) { "🔗" }
        end

        # ── 본문 ──

        def body_group
          own = @design[:body_line_count] # not #body_line_count, which falls back to the paper size's
          inherited = @paper_size.body_line_count.to_s
          label = txt("body_line_count")
          group_box("body", txt("body")) do
            render StyleField.new(field: "body_line_count", state: own.nil? ? :inherited : :changed, label: label,
                                  source: txt("from_paper_size"), parent_text: inherited, error: error("body_line_count"),
                                  editable: @editable, revert_label: txt("revert_body", field: label)) do
              number("body_line_count", label: label, unit: :lines, step: 1, min: 1, max: Design::DocumentDesign::MAX_BODY_LINES,
                     value: shown("body_line_count", own), placeholder: inherited)
            end
          end
        end

        # ── 단 ──

        def columns_group
          group_box("columns", txt("columns")) do
            rows do
              plain_field("column_count") do
                number("column_count", label: txt("column_count"), unit: :none, step: 1, min: 1,
                       max: Design::DocumentDesign::MAX_COLUMNS, value: shown("column_count", @design.column_count))
              end
              plain_field("gutter") do
                number("gutter", label: txt("gutter"), unit: :pt, step: 0.1, min: 0, value: shown("gutter", @design.gutter))
              end
            end
            warnings(@design.columns_fit? ? [] : [ I18n.t("design.page_section.errors.no_column_width") ], "columns")
          end
        end

        def plain_field(f)
          div(class: "flex min-w-0 flex-col", data: { page_field: f }) do
            yield
            p(class: "mt-0.5 text-xs text-red-600", role: "alert", data: { field_error: f }) { error(f) } if error(f)
          end
        end

        # ── shared ──

        def number(f, label:, unit:, step:, value:, min: nil, max: nil, placeholder: nil)
          render Design::Views::Inputs::NumberField.new(
            name: "page[#{f}]", form: FORM_ID, value: value, placeholder: placeholder, label: label,
            unit: unit, step: step, min: min, max: max, disabled: !@editable)
        end

        def error(f) = Array(@field_errors[f]).first

        # After a 422, the value the user tried; otherwise the stored one.
        def shown(f, stored) = @attempted.key?(f) ? @attempted[f].to_s : display(stored)

        def display(value)
          case value
          when nil then nil
          when BigDecimal then value.to_s("F")
          else value.to_s
          end
        end

        def warnings(messages, group)
          messages.each { |m| p(class: "mt-1 text-xs text-amber-700", data: { page_warning: group }) { m } }
        end
      end
    end
  end
end
