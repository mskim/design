module Design
  module Views
    module Inputs
      # A 3 x 3 anchor proxy (design--anchor-grid) over a hidden input: nine
      # buttons in reading order — 1 top-left, 5 centre, 9 bottom-right — the
      # same order DocLayout::Grid places boxes and the renderers crop images.
      # The pressed cell is the stored (or effective) value; picking one writes
      # the hidden input and dispatches one bubbling `change`, which the Object
      # section's autosave turns into a save. There is no "default" cell: a
      # field with an effective default shows it pressed, and × reverts it.
      #
      # crop: this grid picks which part of an image stays in view rather than
      # where a box sits, so the group is named as a crop point.
      # joint_with: fields this one must be written together with
      # (data-joint-with, read by field_save_jobs.js). input_data: extra data
      # attributes for the hidden input (the mini grid's anchorInput target).
      class AnchorGrid < Design::Views::Base
        POSITIONS = (1..9).to_a.freeze
        CELL = "flex h-7 items-center justify-center rounded border border-slate-300 bg-white text-[10px] " \
               "tabular-nums text-slate-500 hover:border-slate-400 aria-pressed:border-slate-900 " \
               "aria-pressed:bg-slate-900 aria-pressed:text-white disabled:opacity-50".freeze

        def initialize(name:, value:, label:, form: nil, crop: false, disabled: false, joint_with: [], input_data: {})
          @name = name
          @value = value
          @label = label
          @form = form
          @crop = crop
          @disabled = disabled
          @joint_with = Array(joint_with)
          @input_data = input_data
        end

        def self.label_for(position) = I18n.t("design.object_section.anchors.a#{position}")

        def view_template
          div(class: "mt-1", data: { controller: "design--anchor-grid", crop: ("true" if @crop),
                                     action: "turbo:morph-element->design--anchor-grid#resync" }) do
            input(type: "hidden", name: @name, form: @form, value: @value, disabled: (true if @disabled),
                  data: { "design--anchor-grid-target": "input", joint_with: @joint_with.presence&.join(" ") }
                          .merge(@input_data.transform_keys(&:to_sym)))
            div(class: "grid grid-cols-3 gap-1", role: "group", aria: { label: group_label }) do
              POSITIONS.each { |position| cell(position) }
            end
          end
        end

        private

        def group_label = I18n.t("design.object_section.#{@crop ? 'crop' : 'position'}")

        def cell(position)
          label = self.class.label_for(position)
          button(type: "button", class: CELL, title: label, disabled: (true if @disabled),
                 aria: { pressed: (position == @value.to_i).to_s, label: label },
                 data: { anchor: position, action: "click->design--anchor-grid#pick",
                         "design--anchor-grid-target": "cell" }) { position.to_s }
        end
      end
    end
  end
end
