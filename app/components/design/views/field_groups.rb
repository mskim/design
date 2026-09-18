module Design
  module Views
    # Shared "group box + inline row" form styling, so the paragraph-style Fields
    # panel and the document PropertiesPanel (layout / header-footer tabs) look the
    # same. Include this module in a Phlex view; it provides group_box, rows,
    # field_row, and the control class constants.
    module FieldGroups
      # One neutral look for every group box — per-group pastel colours were
      # distracting. The key still names the box (data-group) for tests/hooks.
      GROUP_BOX_CLASS = "bg-slate-50 border-slate-200".freeze
      GROUP_LEGEND_CLASS = "bg-slate-100 text-slate-700".freeze

      CONTROL = "min-w-0 flex-1 h-8 rounded border border-slate-300 bg-white px-2 text-sm text-slate-900".freeze
      # Numbers are short — a narrow fixed input frees the label column.
      NUMBER_CONTROL = "h-8 w-16 shrink-0 rounded border border-slate-300 bg-white px-2 text-sm text-slate-900".freeze

      # A fieldset box with the legend chip on the top-left of the border.
      def group_box(key, legend_text)
        fieldset(class: "mb-2.5 rounded-lg border #{GROUP_BOX_CLASS} px-3 pb-3 pt-1.5", data: { group: key }) do
          legend(class: "ml-1 rounded px-2 py-0.5 text-sm font-semibold #{GROUP_LEGEND_CLASS}") { legend_text }
          yield
        end
      end

      # Two-column grid inside a box.
      def rows(&block)
        div(class: "grid grid-cols-2 gap-x-3 gap-y-2.5", &block)
      end

      # Inline row: right-aligned label + control on one line. `narrow: true` (number
      # fields with a fixed-width input) lets the label flex to fill the freed space.
      def field_row(label_text, span: false, narrow: false)
        label_cls = narrow ? "min-w-0 flex-1 text-right text-sm leading-tight text-slate-600"
                           : "w-16 shrink-0 text-right text-sm leading-tight text-slate-600"
        div(class: "ps-field flex min-w-0 items-center gap-2 #{'col-span-2' if span}".rstrip) do
          label(class: label_cls) { label_text }
          yield
        end
      end
    end
  end
end
