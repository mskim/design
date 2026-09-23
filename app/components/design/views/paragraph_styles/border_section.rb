module Design
  module Views
    module ParagraphStyles
      # The 테두리 section's body in the style panel (D5). Included in
      # StylePanelContent: it uses that class's `field`, `field_state`,
      # `display`, `own`, `parent`, `rows`, `field_row` and its
      # @field_errors / @attempted / @editable.
      #
      # Two 🔗 boxes, the border (thickness + colour) and the corners. A box
      # renders linked when its four effective values match (BorderLinkState);
      # after that the toggle is client state (design--style-autosave#toggleLink
      # flips aria-pressed and the box's data-linked, both kept through morphs).
      # The split controls are ordinary style fields, always in the DOM and
      # hidden while linked. A linked control is named paragraph_style_link[<group>]
      # (a stable id; never a field) inside a [data-link-group][data-link-fields]
      # row: committing it writes the whole group, × reverts it
      # (design--style-autosave#groupChanged / #revertGroup).
      module BorderSection
        LINK_PREFIX = "paragraph_style_link"
        # Spelled out for Tailwind's scanner: one named group per box.
        BOX_CLASS = { "border" => "group/border flex flex-col gap-1.5",
                      "corners" => "group/corners flex flex-col gap-1.5" }.freeze
        LINKED_ONLY = { "border" => "grid grid-cols-2 gap-x-3 group-data-[linked=false]/border:hidden",
                        "corners" => "group-data-[linked=false]/corners:hidden" }.freeze
        SPLIT_ONLY = { "border" => "group-data-[linked=true]/border:hidden",
                       "corners" => "group-data-[linked=true]/corners:hidden" }.freeze
        SKETCH_ACTIONS = [ "input->design--box-sketch#draw", "change->design--box-sketch#draw",
                           "click->design--box-sketch#draw", "turbo:morph-element->design--box-sketch#draw" ].join(" ").freeze

        private

        def border_state = @border_state ||= Design::BorderLinkState.new(own: own, parent: parent)

        def border_section_body
          div(class: "flex flex-col gap-3", data: sketch_data) do
            link_box("border") do
              linked_row("border_thickness")
              linked_row("border_color")
            end
            link_box("corners") { linked_row("corners") }
            div(class: "h-12 w-24 self-center bg-white", aria: { hidden: "true" },
                data: { "design--box-sketch-target": "box" })
          end
        end

        def link_box(box, &block)
          linked = border_state.linked?(box)
          label_id = "border-box-#{box}-label"
          div(class: BOX_CLASS.fetch(box), role: "group", aria: { labelledby: label_id },
              data: { link_box: box, linked: linked.to_s }) do
            div(class: "flex items-center justify-between") do
              span(id: label_id, class: "text-xs font-medium text-slate-600") { I18n.t("design.border_controls.boxes.#{box}") }
              link_toggle(box, linked)
            end
            div(class: LINKED_ONLY.fetch(box), &block)
            div(class: SPLIT_ONLY.fetch(box)) { rows { box_fields(box).each { |f| field(f) } } }
          end
        end

        def link_toggle(box, linked)
          button(type: "button", aria: { pressed: linked.to_s, label: I18n.t("design.border_controls.link.#{box}") },
                 disabled: (true unless @editable),
                 class: "rounded px-1.5 text-sm text-slate-400 hover:bg-slate-200 aria-pressed:text-blue-600 disabled:opacity-50",
                 data: { link_toggle: box, action: "design--style-autosave#toggleLink" }) { "🔗" }
        end

        # The split fields in panel order (thickness/colour per side; corners as a 2 x 2 grid).
        def box_fields(box)
          fields = StylePanelContent::SECTIONS.fetch("border")
          box == "border" ? fields - Design::ParagraphStyle::CORNER_FIELDS : fields & Design::ParagraphStyle::CORNER_FIELDS
        end

        def linked_row(group)
          state = border_state.group_state(group, border_field_states)
          active = @editable && state != :inherited
          error = Array(@field_errors[group]).first
          div(class: "flex min-w-0 flex-col",
              data: { link_group: group, link_fields: border_state.fields(group).join(" "), state: state }) do
            div(class: "flex min-w-0 items-center gap-1") do
              span(class: "h-1.5 w-1.5 shrink-0 rounded-full #{StyleField::DOT.fetch(state)}",
                   aria: { hidden: "true" }, data: { dot: true })
              div(class: "min-w-0 flex-1") { linked_control(group) }
              button(type: "button", disabled: (true unless active), tabindex: (active ? nil : "-1"),
                     class: "h-5 w-5 shrink-0 rounded text-sm leading-none text-slate-400 hover:bg-slate-200 hover:text-slate-700#{' invisible' unless active}",
                     aria: { label: I18n.t("design.border_controls.revert_group", group: group_label(group)) },
                     data: { action: "design--style-autosave#revertGroup" }) { "×" }
            end
            p(class: "mt-0.5 text-xs text-red-600", role: "alert", data: { field_error: group }) { error } if error
          end
        end

        def linked_control(group)
          name = "#{LINK_PREFIX}[#{group}]"
          value = @attempted.key?(group) ? @attempted[group].to_s : display(border_state.common_own(group))
          shared = border_state.common_effective(group)
          mixed = shared == Design::BorderLinkState::MIXED
          mixed_label = I18n.t("design.border_controls.mixed") if mixed
          label = group_label(group)
          case group
          when "border_thickness"
            render Design::Views::Inputs::NumberField.new(
              name: name, value: value, label: label, unit: :pt, step: 0.1, min: 0,
              placeholder: mixed_label || display(shared), disabled: !@editable)
          when "border_color"
            render Design::Views::Inputs::ColorField.new(
              name: name, value: value.to_s, label: label, inherited_value: (shared unless mixed),
              empty_label: mixed_label, disabled: !@editable)
          when "corners"
            id = Design::Views::Inputs::InheritSelect.default_id(name)
            field_row(label, for: id) do
              render Design::Views::Inputs::InheritSelect.new(
                name: name, id: id, value: value, options: Design::ParagraphStyle::CORNER_SIZES,
                i18n_scope: "corner_size", inherited_value: (shared unless mixed), placeholder: mixed_label,
                disabled: !@editable)
            end
          end
        end

        def border_field_states = @border_field_states ||= Design::ParagraphStyle::BORDER_FIELDS.index_with { |f| field_state(f) }

        def group_label(group) = I18n.t("design.border_controls.groups.#{group}")

        # The sketch redraws from the controls; the server's effective values
        # fill in whatever a control leaves empty (an inherited field).
        def sketch_data
          effective = Design::ParagraphStyle::BORDER_FIELDS.to_h { |f| [ f, display(border_state.effective(f)).to_s ] }
          { controller: "design--box-sketch", action: SKETCH_ACTIONS,
            "design--box-sketch-effective-value": effective.to_json }
        end
      end
    end
  end
end
