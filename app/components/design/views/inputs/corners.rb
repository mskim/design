module Design
  module Views
    module Inputs
      # Four toggles for a "tl,tr,br,bl" rounded-corner flag string ("1,0,0,1")
      # in a hidden input (design--corner-editor). inherited_value: the parent's
      # corners, shown (muted) and toggled from while this row inherits.
      class Corners < Design::Views::Base
        BUTTON = "w-6 h-6 text-xs cursor-pointer border border-slate-300 flex items-center justify-center bg-white".freeze
        ROUNDED = { "tl" => "rounded-tl-md", "tr" => "rounded-tr-md", "bl" => "rounded-bl-md", "br" => "rounded-br-md" }.freeze

        def initialize(name:, value:, inherited_value: nil, disabled: false)
          @name = name
          @value = value.presence
          @inherited = inherited_value.to_s.presence
          @disabled = disabled
        end

        def view_template
          div do
            label(class: "text-xs text-slate-600") { I18n.t("design.fields.rounded_corners") }
            div(class: "mt-0.5", data: { controller: "design--corner-editor",
                                         "design--corner-editor-parent-value": @inherited,
                                         action: "turbo:morph-element->design--corner-editor#updateVisual" }) do
              input(type: "hidden", name: @name, value: @value, disabled: disabled,
                    data: { "design--corner-editor-target": "input" })
              div(class: "flex flex-col items-center gap-0.5") do
                div(class: "flex gap-8") do
                  corner("tl")
                  corner("tr")
                end
                div(class: "w-14 h-8 bg-white border border-slate-300", data: { "design--corner-editor-target": "box" })
                div(class: "flex gap-8") do
                  corner("bl")
                  corner("br")
                end
              end
            end
          end
        end

        private

        def disabled = (true if @disabled)

        def corner(name)
          button(type: "button", class: "#{BUTTON} #{ROUNDED.fetch(name)}", disabled: disabled,
                 data: { action: "click->design--corner-editor#toggle", corner: name, "design--corner-editor-target": name })
        end
      end
    end
  end
end
