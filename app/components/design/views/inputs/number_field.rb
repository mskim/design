module Design
  module Views
    module Inputs
      # A text input for numbers with designer-tool behaviour (design--scrub-input):
      # drag the label to scrub, arrows to step, typed maths and units. The input keeps
      # the form's original `name`, so params are unchanged; `name: nil` is for popover
      # sub-fields that must not submit. The component owns its label (the scrub handle).
      class NumberField < Design::Views::Base
        UNITS = %i[pt mm lines percent none].freeze
        LAYOUTS = %i[inline stacked compact].freeze
        INPUT_ACTIONS = "focus->design--scrub-input#remember keydown->design--scrub-input#keydown blur->design--scrub-input#commit".freeze
        HANDLE_ACTIONS = "pointerdown->design--scrub-input#scrubStart pointermove->design--scrub-input#scrubMove " \
                         "pointerup->design--scrub-input#scrubEnd pointercancel->design--scrub-input#scrubEnd " \
                         "lostpointercapture->design--scrub-input#scrubEnd click->design--scrub-input#handleClick".freeze

        def initialize(value:, label:, name: nil, unit: :pt, step: 0.1, min: nil, max: nil,
                       layout: :inline, placeholder: nil, disabled: false, span: false, id: nil, input_data: {})
          raise ArgumentError, "unknown unit #{unit.inspect}" unless UNITS.include?(unit)
          raise ArgumentError, "unknown layout #{layout.inspect}" unless LAYOUTS.include?(layout)
          raise ArgumentError, "step must be a positive number, got #{step.inspect}" unless step.is_a?(Numeric) && step.positive?
          @value = value
          @label = label
          @name = name
          @unit = unit
          @step = step
          @min = min
          @max = max
          @layout = layout
          @placeholder = placeholder
          @disabled = disabled
          @span = span
          @id = id || (name ? "nf-#{self.class.dom_key(name)}" : "nf-#{SecureRandom.hex(4)}")
          @input_data = input_data
        end

        # A stable id fragment for a field name ("paragraph_style[font_size]" →
        # "paragraph_style-font_size"): a Turbo morph reuses (and keeps focus on)
        # a control only when its id is the same across renders.
        def self.dom_key(name) = name.to_s.gsub(/[^A-Za-z0-9_-]+/, "-").gsub(/\A-+|-+\z/, "")

        def view_template
          div(class: wrapper_class, data: controller_data) do
            label(for: @id, class: label_class, data: { "design--scrub-input-target": "handle", action: HANDLE_ACTIONS }) { @label }
            div(class: box_class) do
              # class/data come BEFORE name: existing tests assert editable fields with
              # /name="…"[^>]*disabled/ and the class string contains "disabled:" variants.
              input(class: input_class, data: input_data,
                    id: @id, type: "text", inputmode: "decimal", autocomplete: "off", spellcheck: "false",
                    name: @name, value: @value, placeholder: @placeholder, disabled: (@disabled || nil),
                    "aria-describedby": (suffix_id if suffix))
              span(id: suffix_id, class: suffix_class, data: { unit_suffix: true }) { suffix } if suffix
            end
          end
        end

        private

        # A caller's `action:` is appended to the scrub actions rather than replacing them.
        def input_data
          extra = @input_data.transform_keys(&:to_sym)
          action = [ INPUT_ACTIONS, extra.delete(:action) ].compact.join(" ")
          { "design--scrub-input-target": "input", action: action }.merge(extra)
        end

        def suffix_id = "#{@id}-suffix"

        def controller_data
          {
            controller: "design--scrub-input",
            action: "turbo:morph-element->design--scrub-input#resync",
            "design--scrub-input-unit-value": @unit,
            "design--scrub-input-step-value": @step,
            "design--scrub-input-min-value": @min,
            "design--scrub-input-max-value": @max
          }
        end

        def suffix
          case @unit
          when :pt then "pt"
          when :mm then "mm"
          when :percent then "%"
          when :lines then I18n.t("design.inputs.lines")
          end
        end

        # A named group (`group/nf`) + data-invalid (toggled by JS) drives the red outline,
        # so an enclosing `group` can't trigger it; the classes live here in Ruby where
        # Tailwind's scanner sees them.
        def wrapper_class
          base = case @layout
                 when :inline  then "ps-field group/nf flex min-w-0 items-center gap-2"
                 when :stacked then "group/nf flex flex-col"
                 when :compact then "group/nf relative"
                 end
          [ base, ("col-span-2" if @span) ].compact.join(" ")
        end

        def label_class
          handle = "cursor-ew-resize select-none touch-none"
          case @layout
          when :inline  then "min-w-0 flex-1 text-right text-sm leading-tight text-slate-600 #{handle}"
          when :stacked then "mb-0.5 block text-xs text-slate-500 #{handle}"
          when :compact then "absolute left-1.5 top-1/2 z-10 -translate-y-1/2 text-[10px] font-medium text-slate-400 #{handle}"
          end
        end

        def box_class
          case @layout
          when :inline  then "relative h-8 w-20 shrink-0"
          when :stacked then "relative"
          when :compact then "relative"
          end
        end

        def input_class
          common = "w-full rounded border border-slate-300 bg-white text-slate-900 tabular-nums " \
                   "group-data-[invalid]/nf:border-red-500 group-data-[invalid]/nf:ring-1 group-data-[invalid]/nf:ring-red-500 " \
                   "disabled:bg-slate-50 disabled:text-slate-400 placeholder:italic placeholder:text-slate-400"
          case @layout
          when :inline  then "#{common} h-8 px-2 text-sm #{'pr-7' if suffix}"
          when :stacked then "#{common} px-2.5 py-1 text-sm #{'pr-8' if suffix}"
          when :compact then "#{common} h-7 pl-5 pr-4 text-xs"
          end
        end

        def suffix_class
          "pointer-events-none absolute right-1.5 top-1/2 -translate-y-1/2 text-[10px] text-slate-400"
        end
      end
    end
  end
end
