module Design
  module Views
    module DocumentDesigns
      # The Object section (D4): the Layout tab's inspector for this doc type's
      # one grid-placed object — copyright's text box, the front wing's author
      # photo — built like D3's Page section. It is a div, not a form:
      # design--style-autosave builds its own requests, and the controls carry
      # form="object-section-form" (an empty form PropertiesPanel renders outside
      # the tabs form), so live preview and Save never send them. Saves morph
      # only ObjectSectionContent.
      #
      # urls: { field: object/field endpoint, preview: the preview frame's GET
      # URL (reloaded when a failed save left it stale) }.
      class ObjectSection < Design::Views::Base
        ACTIONS = [
          "change->design--style-autosave#fieldChanged",
          "turbo:before-morph-attribute->design--style-autosave#keepLocalState",
          "turbo:before-morph-element->design--style-autosave#keepOpenPopover"
        ].join(" ").freeze

        def initialize(document_design:, urls:, editable: true)
          @document_design = document_design
          @urls = urls
          @editable = editable
        end

        def view_template
          return if @document_design.object_fields.empty?

          div(class: "mb-2.5", data: section_data) do
            div(class: "mb-1.5 flex items-center justify-between") do
              h3(class: "text-sm font-semibold text-slate-800") { I18n.t("design.object_section.title") }
              span(class: "text-xs text-slate-500 data-[status=error]:text-red-600", role: "status",
                   aria: { live: "polite" }, data: { "design--style-autosave-target": "status" })
            end
            render ObjectSectionContent.new(document_design: @document_design, editable: @editable)
          end
        end

        private

        # No required-fields value: every field here either has a column default
        # or means "the engine's default" when nil, so emptying one is a revert.
        def section_data
          {
            object_section: true,
            controller: "design--style-autosave",
            action: ACTIONS,
            "design--style-autosave-field-url-value": @urls[:field],
            "design--style-autosave-preview-url-value": @urls[:preview],
            "design--style-autosave-field-prefix-value": "object",
            "design--style-autosave-panel-target-value": ObjectSectionContent::TARGET,
            "design--style-autosave-saving-text-value": I18n.t("design.style_panel.status.saving"),
            "design--style-autosave-saved-text-value": I18n.t("design.style_panel.status.saved"),
            "design--style-autosave-error-text-value": I18n.t("design.style_panel.status.error")
          }
        end
      end
    end
  end
end
