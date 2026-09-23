module Design
  module Views
    module Inputs
      # Compact colour row (design--color-row): swatch + summary; a popover edits CMYK
      # (four scrubbable fields + K slider) or hex (text + native picker). The stored
      # text lives in a hidden input with the form's original name, unchanged format.
      # formats: [:hex] for columns whose consumers only read hex (table styles, gradients).
      # form: ties the hidden value to another <form> (the Object section's), so the
      # enclosing form never submits it.
      class ColorField < Design::Views::Base
        def initialize(name:, value:, label:, layout: :inline, formats: [ :cmyk, :hex ], disabled: false, span: false,
                       inherited_value: nil, form: nil)
          @name = name
          @value = value.to_s
          @label = label
          @layout = layout
          @formats = formats
          @disabled = disabled
          @span = span
          @inherited_value = inherited_value.to_s.strip
          @form = form
          # Stable when named (a morph must keep the row, its popover and focus).
          @uid = name.present? ? "cf-#{NumberField.dom_key(name)}" : "cf-#{SecureRandom.hex(4)}"
        end

        def view_template
          div(class: wrapper_class,
              data: { controller: "design--color-row",
                      "design--color-row-formats-value": @formats.join(","),
                      "design--color-row-inherit-value": I18n.t("design.inputs.inherit"),
                      "design--color-row-parent-value": @inherited_value.presence }) do
            span(id: label_id, class: label_class) { @label }
            div(class: "relative min-w-0 flex-1") do
              input(type: "hidden", name: @name, form: @form, value: @value, disabled: (@disabled || nil),
                    data: { "design--color-row-target": "value" })
              trigger
              popover
            end
          end
        end

        private

        # Inherited (no own value) with a parent colour to show.
        def inherited? = @value.strip.empty? && !@inherited_value.empty?
        def shown = inherited? ? @inherited_value : @value

        def label_id = "#{@uid}-label"
        def summary_id = "#{@uid}-summary"
        def popover_id = "#{@uid}-popover"

        def trigger
          button(type: "button", disabled: (@disabled || nil),
                 class: "flex h-8 w-full min-w-0 items-center gap-2 rounded border border-slate-300 bg-white px-2 text-left text-sm tabular-nums hover:border-slate-400 disabled:bg-slate-50 disabled:text-slate-400",
                 aria: { labelledby: "#{label_id} #{summary_id}", haspopup: "dialog", controls: popover_id, expanded: "false" },
                 data: { "design--color-row-target": "trigger", action: "click->design--color-row#toggle" }) do
            span(class: "h-5 w-5 shrink-0 rounded border border-slate-300", aria: { hidden: "true" },
                 style: ColorValue.swatch_style(shown), data: { "design--color-row-target": "swatch" })
            span(id: summary_id, class: "truncate data-[inherited]:italic data-[inherited]:text-slate-400",
                 data: { "design--color-row-target": "summary", inherited: (true if inherited?) }) do
              if @value.strip.empty?
                inherited? ? ColorValue.summary(@inherited_value) : I18n.t("design.inputs.inherit")
              else
                ColorValue.summary(@value)
              end
            end
          end
        end

        def popover
          div(id: popover_id, hidden: true, role: "dialog", aria: { label: @label },
              class: "fixed z-50 w-60 rounded-lg border border-slate-200 bg-white p-2 shadow-lg",
              data: { "design--color-row-target": "popover" }) do
            mode_switch if @formats.size > 1
            cmyk_panel if @formats.include?(:cmyk)
            hex_panel if @formats.include?(:hex)
            div(class: "mt-2 flex justify-end") do
              button(type: "button", class: "text-xs text-slate-500 hover:text-slate-800",
                     data: { action: "click->design--color-row#clear" }) { I18n.t("design.inputs.clear") }
            end
          end
        end

        def mode_switch
          div(class: "mb-2 inline-flex overflow-hidden rounded border border-slate-200 text-xs") do
            @formats.each do |fmt|
              button(type: "button", class: "px-2 py-0.5 data-[active]:bg-slate-900 data-[active]:text-white", aria: { pressed: "false" },
                     data: { mode: fmt, "design--color-row-target": "modeButton", action: "click->design--color-row#selectMode" }) do
                I18n.t("design.inputs.#{fmt}")
              end
            end
          end
        end

        def cmyk_panel
          div(data: { "design--color-row-target": "cmykPanel", action: cmyk_panel_actions }) do
            div(class: "grid grid-cols-4 gap-1") do
              %w[c m y k].each do |ch|
                render NumberField.new(name: nil, value: nil, label: ch.upcase, unit: :percent, step: 1, min: 0, max: 100,
                                       layout: :compact, id: "#{@uid}-#{ch}", input_data: { channel: ch })
              end
            end
            input(type: "range", min: 0, max: 100, step: 1, class: "mt-2 w-full", aria: { label: "K" },
                  data: { "design--color-row-target": "kSlider", action: "input->design--color-row#fromSlider" })
          end
        end

        # focusin remembers the stored text so a channel's Escape/invalid revert restores it;
        # input stores live, change (commit) stores and re-shows what was stored.
        def cmyk_panel_actions
          [ "focusin->design--color-row#rememberField",
            "input->design--color-row#fromChannels",
            "change->design--color-row#commitChannels",
            "design--scrub-input:revert->design--color-row#revertField" ].join(" ")
        end

        def hex_panel
          div(class: "flex items-center gap-1", data: { "design--color-row-target": "hexPanel" }) do
            input(type: "text", placeholder: "#rrggbb", spellcheck: "false", autocomplete: "off", aria: { label: "Hex" },
                  class: "h-7 min-w-0 flex-1 rounded border border-slate-300 px-2 text-xs tabular-nums",
                  data: { "design--color-row-target": "hexInput", action: "input->design--color-row#fromHex keydown->design--color-row#hexKeydown" })
            button(type: "button", class: "rounded border border-slate-300 px-2 py-1 text-xs",
                   data: { action: "click->design--color-row#openPicker" }) { I18n.t("design.inputs.picker") }
            input(type: "color", class: "sr-only", tabindex: -1,
                  data: { "design--color-row-target": "picker", action: "input->design--color-row#fromPicker change->design--color-row#fromPicker" })
          end
        end

        def wrapper_class
          base = @layout == :stacked ? "flex flex-col" : "ps-field flex min-w-0 items-center gap-2"
          [ base, ("col-span-2" if @span) ].compact.join(" ")
        end

        def label_class
          @layout == :stacked ? "mb-0.5 block text-xs text-slate-500" : "w-16 shrink-0 text-right text-sm leading-tight text-slate-600"
        end
      end
    end
  end
end
