module Design
  module Views
    module Inputs
      # Four toggles for a "top,right,bottom,left" flag string ("1,0,1,0") in a
      # hidden input (design--border-side-editor). inherited_value: the parent's
      # sides, shown (muted) and toggled from while this row inherits.
      class BorderSides < Design::Views::Base
        BUTTON = "text-xs cursor-pointer border border-slate-300 rounded bg-white".freeze

        def initialize(name:, value:, inherited_value: nil, disabled: false)
          @name = name
          @value = value.presence
          @inherited = inherited_value.to_s.presence
          @disabled = disabled
        end

        def view_template
          div do
            label(class: "text-xs text-slate-600") { I18n.t("design.fields.border_sides") }
            div(class: "mt-0.5", data: { controller: "design--border-side-editor",
                                         "design--border-side-editor-parent-value": @inherited,
                                         action: "turbo:morph-element->design--border-side-editor#updateVisual" }) do
              input(type: "hidden", name: @name, value: @value, disabled: disabled,
                    data: { "design--border-side-editor-target": "input" })
              div(class: "flex flex-col items-center gap-0.5") do
                side("top", "px-3 py-0.5")
                div(class: "flex items-center gap-0.5") do
                  side("left", "px-0.5 py-1.5")
                  div(class: "w-14 h-10 bg-white border border-dashed border-slate-300", data: { "design--border-side-editor-target": "box" })
                  side("right", "px-0.5 py-1.5")
                end
                side("bottom", "px-2 py-0.5")
              end
            end
          end
        end

        private

        def disabled = (true if @disabled)

        def side(name, pad)
          button(type: "button", class: "#{pad} #{BUTTON}", disabled: disabled,
                 data: { action: "click->design--border-side-editor#toggle", side: name }) { I18n.t("design.shared.#{name}") }
        end
      end
    end
  end
end
