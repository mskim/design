module Design
  module Views
    # Shared "pastel group box + inline row" form styling, so the paragraph-style
    # Fields panel and the document PropertiesPanel (layout / header-footer tabs)
    # look the same. Include this module in a Phlex view; it provides group_box,
    # rows, field_row, and the control class constants.
    module FieldGroups
      TINTS = {
        "basic"     => [ "bg-blue-50 border-blue-200",       "bg-blue-100 text-blue-800" ],
        "type_text" => [ "bg-emerald-50 border-emerald-200", "bg-emerald-100 text-emerald-800" ],
        "table"     => [ "bg-slate-50 border-slate-200",     "bg-slate-100 text-slate-700" ],
        "bold"      => [ "bg-amber-50 border-amber-200",     "bg-amber-100 text-amber-800" ],
        "space"     => [ "bg-violet-50 border-violet-200",   "bg-violet-100 text-violet-800" ],
        "fill"      => [ "bg-pink-50 border-pink-200",       "bg-pink-100 text-pink-800" ],
        "border"    => [ "bg-cyan-50 border-cyan-200",       "bg-cyan-100 text-cyan-800" ],
        "pad"       => [ "bg-orange-50 border-orange-200",   "bg-orange-100 text-orange-800" ],
        # extra tints for the properties panel
        "rose"      => [ "bg-rose-50 border-rose-200",       "bg-rose-100 text-rose-800" ],
        "teal"      => [ "bg-teal-50 border-teal-200",       "bg-teal-100 text-teal-800" ],
        "sky"       => [ "bg-sky-50 border-sky-200",         "bg-sky-100 text-sky-800" ],
        "lime"      => [ "bg-lime-50 border-lime-200",       "bg-lime-100 text-lime-800" ],
        "indigo"    => [ "bg-indigo-50 border-indigo-200",   "bg-indigo-100 text-indigo-800" ]
      }.freeze

      CONTROL = "min-w-0 flex-1 h-8 rounded border border-slate-300 bg-white px-2 text-sm text-slate-900".freeze
      # Numbers are short — a narrow fixed input frees the label column.
      NUMBER_CONTROL = "h-8 w-16 shrink-0 rounded border border-slate-300 bg-white px-2 text-sm text-slate-900".freeze

      # A tinted fieldset box with the legend chip on the top-left of the border.
      def group_box(key, legend_text)
        box_cls, leg_cls = TINTS.fetch(key)
        fieldset(class: "mb-2.5 rounded-lg border #{box_cls} px-3 pb-3 pt-1.5", data: { group: key }) do
          legend(class: "ml-1 rounded px-2 py-0.5 text-sm font-semibold #{leg_cls}") { legend_text }
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
