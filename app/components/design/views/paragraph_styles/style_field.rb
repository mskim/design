module Design
  module Views
    module ParagraphStyles
      # One field of the style panel: a state dot, the control (the block), and
      # × (revert to inherit), with a validation message underneath.
      #   :inherited — the control is empty; its placeholder is the parent's
      #                value; the title names where it comes from.
      #   :changed   — set by the user for this doc type: blue dot, ×.
      #   :generated — stored but not user-marked (a size-generator value):
      #                pale dot titled "자동 크기 조정"; still revertible.
      class StyleField < Design::Views::Base
        STATES = %i[inherited changed generated].freeze
        DOT = { changed: "bg-blue-600", generated: "bg-blue-300", inherited: "bg-transparent" }.freeze

        # label: the field's label, named in ×'s aria-label. revert_label: a
        # different aria-label for × (the Page section's "규칙 값으로 되돌리기").
        def initialize(field:, state:, label: nil, source: nil, parent_text: nil, error: nil, editable: true, span: false,
                       revert_label: nil)
          raise ArgumentError, "unknown state #{state.inspect}" unless STATES.include?(state)
          @field = field
          @label = label || field
          @state = state
          @source = source
          @parent_text = parent_text
          @error = error
          @editable = editable
          @span = span
          @revert_label = revert_label
        end

        def view_template
          div(class: [ "flex min-w-0 flex-col", ("col-span-2" if @span) ].compact.join(" "),
              title: title, data: { style_field: @field, state: @state }) do
            div(class: "flex min-w-0 items-center gap-1") do
              span(class: "h-1.5 w-1.5 shrink-0 rounded-full #{DOT.fetch(@state)}", aria: { hidden: "true" }, data: { dot: true })
              div(class: "min-w-0 flex-1") { yield }
              revert_button
            end
            p(class: "mt-0.5 text-xs text-red-600", role: "alert", data: { field_error: @field }) { @error } if @error
          end
        end

        private

        # Inherited: "테마에서: 10.0". Nothing to name when the parent has no
        # value either (a parentless style), so no title at all.
        def title
          case @state
          when :inherited then "#{@source}: #{@parent_text}" if @parent_text
          when :generated then I18n.t("design.style_panel.generated")
          end
        end

        # Always rendered (invisible when there is nothing to revert), so the row
        # keeps its shape and a morph updates it in place.
        def revert_button
          active = @editable && @state != :inherited
          button(type: "button", disabled: (true unless active), tabindex: (active ? nil : "-1"),
                 class: "h-5 w-5 shrink-0 rounded text-sm leading-none text-slate-400 hover:bg-slate-200 hover:text-slate-700#{' invisible' unless active}",
                 aria: { label: @revert_label || I18n.t("design.style_panel.revert_field", field: @label) },
                 data: { action: "design--style-autosave#revert", field: @field }) { "×" }
        end
      end
    end
  end
end
