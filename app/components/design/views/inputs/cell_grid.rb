module Design
  module Views
    module Inputs
      # The mini grid: the page's (or the flap's) grid drawn at its own aspect
      # ratio with the box on it. design--cell-grid — declared on the enclosing
      # group, which also holds the cell-size fields and the anchor grid —
      # redraws the box from those fields and, from the handle, resizes it by
      # whole cells with the anchor's own corner fixed (cell_grid.js).
      #
      # cell: { x:, y:, w:, h: } in cells (DocumentDesign#text_box_cell /
      # #photo_cell). draggable: false renders the sketch without a handle — the
      # front wing's photo floats inside the body text box, so its sketch shows
      # a size, not a position.
      class CellGrid < Design::Views::Base
        LINE = "#e2e8f0".freeze
        HANDLE = "absolute h-3 w-3 cursor-nwse-resize rounded-sm border border-slate-900 bg-white".freeze
        # The free corner: the one opposite the anchor. A centred axis (anchors
        # 2/5/8 across, 4/5/6 down) grows both ways, so the far corner does.
        CORNERS = { [ 0, 0 ] => "-right-1 -bottom-1", [ 1, 0 ] => "-right-1 -bottom-1", [ 2, 0 ] => "-left-1 -bottom-1",
                    [ 0, 1 ] => "-right-1 -bottom-1", [ 1, 1 ] => "-right-1 -bottom-1", [ 2, 1 ] => "-left-1 -bottom-1",
                    [ 0, 2 ] => "-right-1 -top-1",    [ 1, 2 ] => "-right-1 -top-1",    [ 2, 2 ] => "-left-1 -top-1" }.freeze

        def initialize(columns:, rows:, cell:, anchor:, draggable: true, disabled: false, hint: nil)
          @columns = columns
          @rows = rows
          @cell = cell
          @anchor = anchor.to_i.clamp(1, 9)
          @draggable = draggable
          @disabled = disabled
          @hint = hint
        end

        def view_template
          div(class: "mt-2") do
            div(class: "relative w-full overflow-hidden rounded border border-slate-300 bg-white",
                style: "aspect-ratio: #{@columns} / #{@rows};",
                data: { "design--cell-grid-target": "grid" }) do
              div(class: "pointer-events-none absolute inset-0", style: lines_style, aria: { hidden: "true" })
              div(class: "absolute border border-slate-900 bg-slate-900/10", style: box_style,
                  data: { "design--cell-grid-target": "box" }) { handle if handle? }
            end
            p(class: "mt-1 text-xs text-slate-500", data: { cell_grid_hint: true }) { @hint } if @hint
          end
        end

        private

        def handle? = @draggable && !@disabled

        def handle
          button(type: "button", class: "#{HANDLE} #{CORNERS.fetch(corner)}",
                 aria: { label: I18n.t("design.object_section.resize") },
                 data: { "design--cell-grid-target": "handle", action: HANDLE_ACTIONS })
        end

        HANDLE_ACTIONS = [ "pointerdown->design--cell-grid#dragStart", "pointermove->design--cell-grid#dragMove",
                           "pointerup->design--cell-grid#dragEnd", "pointercancel->design--cell-grid#dragEnd",
                           "lostpointercapture->design--cell-grid#dragEnd" ].join(" ").freeze

        def corner = [ (@anchor - 1) % 3, (@anchor - 1) / 3 ]

        # Faint cell lines, in percent, so JS never has to draw them.
        def lines_style
          "background-image: repeating-linear-gradient(to right, #{LINE} 0 1px, transparent 1px #{pct(100.0 / @columns)}%), " \
            "repeating-linear-gradient(to bottom, #{LINE} 0 1px, transparent 1px #{pct(100.0 / @rows)}%)"
        end

        def box_style
          "left: #{pct(100.0 * @cell[:x] / @columns)}%; top: #{pct(100.0 * @cell[:y] / @rows)}%; " \
            "width: #{pct(100.0 * @cell[:w] / @columns)}%; height: #{pct(100.0 * @cell[:h] / @rows)}%;"
        end

        def pct(value) = value.round(3).to_s
      end
    end
  end
end
