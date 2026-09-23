module Design
  module Views
    module DocumentDesigns
      # The morphed part of the Object section (#object-section-content): the
      # inspector for the one grid-placed object this doc type has.
      #
      #   copyright  — the text box: a 3 x 3 anchor proxy, width and height in
      #                grid cells, and a mini grid whose free corner resizes it.
      #   front_wing — the author photo: cell size with a size sketch, the crop
      #                point, fit, and a border.
      #
      # Everything else renders nothing: no other layout reads these columns
      # (front_page and seneca keep the plain controls in the tabs form until
      # the studio previews covers with the real cover renderers).
      #
      # Controls are named object[<field>] and belong to the empty
      # #object-section-form (form=), so the tabs form never sends them;
      # design--style-autosave on the enclosing ObjectSection saves each commit,
      # and data-joint-with marks the ones that must be written together.
      #
      # Dot and × (StyleField): a text-box field when the column is set — × puts
      # it back to nil, which means the engine's 7 / 4 / 6; a photo field when it
      # differs from its column default, which × returns it to.
      class ObjectSectionContent < Design::Views::Base
        include Design::Views::FieldGroups

        FORM_ID = "object-section-form"
        TARGET = "object-section-content"
        CELL_GRID_ACTIONS = [ "change->design--cell-grid#draw", "input->design--cell-grid#draw",
                              "turbo:morph-element->design--cell-grid#draw" ].join(" ").freeze
        StyleField = Design::Views::ParagraphStyles::StyleField
        AnchorGrid = Design::Views::Inputs::AnchorGrid
        CellGrid = Design::Views::Inputs::CellGrid

        # field_errors: { field => [messages] }, attempted: { field => value }
        # (a 422 re-render keeps what the user typed).
        def initialize(document_design:, editable: true, field_errors: {}, attempted: {})
          @design = document_design
          @editable = editable
          @field_errors = field_errors.to_h.transform_keys(&:to_s)
          @attempted = attempted.to_h.transform_keys(&:to_s)
        end

        def view_template
          return if @design.object_fields.empty?

          div(id: TARGET, class: "flex flex-col") do
            case @design.doc_type
            when "copyright" then text_box_group
            when "front_wing" then photo_group
            end
          end
        end

        private

        def txt(key, **opts) = I18n.t("design.object_section.#{key}", **opts)

        # ── copyright: the text box ──

        def text_box_group
          grid = @design.object_grid
          group_box("space", txt("text_box")) do
            div(data: cell_grid_data(grid)) do
              # No joint_with: the engine defaults the three fields separately,
              # so an anchor never needs the sizes written with it (decision 3).
              anchor_row("text_box_anchor_position", label: txt("position"),
                         default_label: AnchorGrid.label_for(Design::DocumentDesign::COPYRIGHT_DEFAULTS[:text_box_anchor_position]),
                         cell_grid_target: "anchorInput")
              rows do
                cell_row("text_box_grid_width", txt("width"), max: grid[:columns], target: "widthInput",
                         joint_with: [ "text_box_grid_height" ])
                cell_row("text_box_grid_height", txt("height"), max: grid[:rows], target: "heightInput",
                         joint_with: [ "text_box_grid_width" ])
              end
              render CellGrid.new(columns: grid[:columns], rows: grid[:rows], cell: @design.text_box_cell(grid),
                                  anchor: @design.effective_text_box_anchor_position, disabled: !@editable)
            end
            # The engine bottom-aligns the text inside the box and grows it
            # upward whatever the anchor (DocLayout::Book::Copyright).
            hint("text_box_hint", :object_hint)
          end
        end

        # ── front_wing: the author photo ──

        def photo_group
          grid = Design::DocumentDesign::PHOTO_GRID
          group_box("space", txt("photo")) do
            div(data: cell_grid_data(grid)) do
              rows do
                cell_row("photo_grid_width", txt("width"), max: grid[:columns], target: "widthInput",
                         joint_with: [ "photo_grid_height" ])
                cell_row("photo_grid_height", txt("height"), max: grid[:rows], target: "heightInput",
                         joint_with: [ "photo_grid_width" ])
              end
              # A size sketch: the photo floats inside the body text box, below
              # the author's name, so it is never really at the grid's top-left.
              render CellGrid.new(columns: grid[:columns], rows: grid[:rows], cell: @design.photo_cell, anchor: 1,
                                  draggable: false, disabled: !@editable, hint: txt("photo_sketch_hint"))
            end
            anchor_row("photo_anchor", label: txt("crop"), crop: true,
                       default_label: AnchorGrid.label_for(default_for("photo_anchor")))
            hint("crop_hint", :crop_hint)
            fit_row
            border_rows
          end
        end

        def fit_row
          style_field("photo_fit", txt("fit")) do
            select(name: name_for("photo_fit"), form: FORM_ID, class: CONTROL, title: txt("fit_hint"),
                   disabled: (true unless @editable)) do
              Design::DocumentDesign::PHOTO_FITS.each do |fit|
                option(value: fit, selected: shown("photo_fit") == fit) { I18n.t("design.options.photo_fit.#{fit}") }
              end
            end
          end
        end

        def border_rows
          rows do
            style_field("photo_border_width", txt("border_width")) do
              render Design::Views::Inputs::NumberField.new(
                name: name_for("photo_border_width"), form: FORM_ID, value: shown("photo_border_width"),
                label: txt("border_width"), unit: :pt, step: 0.1, min: 0, layout: :stacked, disabled: !@editable)
            end
            style_field("photo_border_color", txt("border_color")) do
              # CMYK or hex only: the renderers stroke nothing for a colour name.
              render Design::Views::Inputs::ColorField.new(
                name: name_for("photo_border_color"), form: FORM_ID, value: shown("photo_border_color"),
                label: txt("border_color"), layout: :stacked, formats: [ :cmyk, :hex ], disabled: !@editable)
            end
          end
        end

        # ── shared ──

        def cell_grid_data(grid)
          { controller: "design--cell-grid", action: CELL_GRID_ACTIONS,
            "design--cell-grid-columns-value": grid[:columns], "design--cell-grid-rows-value": grid[:rows] }
        end

        # Neither anchor is written with anything else, so no joint_with here.
        # AnchorGrid keeps that option for the cover panels' future inspector.
        def anchor_row(field, label:, default_label:, crop: false, cell_grid_target: nil)
          style_field(field, label, default_text: default_label) do
            render AnchorGrid.new(name: name_for(field), form: FORM_ID, value: shown(field), label: label,
                                  crop: crop, disabled: !@editable,
                                  input_data: { "design--cell-grid-target": cell_grid_target }.compact)
          end
        end

        def cell_row(field, label, max:, target:, joint_with:)
          style_field(field, label) do
            render Design::Views::Inputs::NumberField.new(
              name: name_for(field), form: FORM_ID, value: shown(field), label: label, unit: :none,
              step: 1, min: 1, max: max, layout: :stacked, disabled: !@editable,
              input_data: { "design--cell-grid-target": target, joint_with: joint_with.join(" ") })
          end
        end

        # The block is passed to render(...), not to .new — a block stored at
        # .new renders nothing in Phlex 2.4 (see Design::Views::Base#shell).
        def style_field(field, label, default_text: nil, &block)
          render(StyleField.new(field: field, state: state(field), label: label, source: txt("default"),
                                parent_text: (default_text || default_for(field).to_s if state(field) == :inherited),
                                error: error(field), editable: @editable,
                                revert_label: txt("revert_field", field: label)), &block)
        end

        # A text-box field is the design's own exactly when its column is set
        # (its default lives in the model, not the column); a photo field when
        # it differs from the column default.
        def state(field)
          own = if Design::DocumentDesign::OBJECT_TEXT_BOX_FIELDS.include?(field)
            !@design[field].nil?
          else
            @design[field].to_s != default_for(field).to_s
          end
          own ? :changed : :inherited
        end

        def default_for(field) = Design::DocumentDesign.column_defaults[field]

        def name_for(field) = "object[#{field}]"

        def error(field) = Array(@field_errors[field]).first

        # After a 422, the value the user tried; otherwise the effective one —
        # what the renderer would use, so the grid and the fields agree.
        #
        # Note the deliberate asymmetry on a 422: the FIELDS show what was
        # typed (so it can be corrected), while the mini grid and the preview
        # guides are drawn from `text_box_cell`, i.e. from the RELOADED stored
        # values — nothing was written, so that is what the page still is. The
        # sketch snaps to the typed values again as soon as they are legal,
        # because design--cell-grid redraws from the fields on every input.
        def shown(field)
          return @attempted[field].to_s if @attempted.key?(field)
          value = Design::DocumentDesign::OBJECT_TEXT_BOX_FIELDS.include?(field) ?
                    @design.public_send("effective_#{field}") : @design[field]
          case value
          when nil then nil
          when BigDecimal then value.to_s("F")
          else value.to_s
          end
        end

        def hint(key, data_key)
          p(class: "mt-1.5 text-xs text-slate-500", data: { data_key => true }) { txt(key) }
        end
      end
    end
  end
end
