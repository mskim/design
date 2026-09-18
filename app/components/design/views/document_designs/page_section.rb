module Design
  module Views
    module DocumentDesigns
      # The Page section (D3): the first box of the design editor's Layout tab,
      # inside the tabs form. It is a div, not a form: design--style-autosave
      # builds its own requests, and the controls carry form="page-section-form"
      # (an empty form PropertiesPanel renders outside the tabs form), so live
      # preview and Save never send them. Saves morph only PageSectionContent.
      #
      # urls: { field: page/field endpoint, preview: the preview frame's GET URL
      # (reloaded when a failed save left it stale), paper_size: 판형 편집 }.
      class PageSection < Design::Views::Base
        ACTIONS = [
          "change->design--style-autosave#fieldChanged",
          "turbo:before-morph-attribute->design--style-autosave#keepLocalState"
        ].join(" ").freeze
        # Never reverted: emptying one is a 422 "필수", not a DELETE.
        REQUIRED_FIELDS = %w[column_count gutter].freeze

        def initialize(document_design:, urls:, editable: true)
          @document_design = document_design
          @urls = urls
          @editable = editable
        end

        def view_template
          div(class: "mb-2.5", data: section_data) do
            div(class: "mb-1.5 flex items-center justify-between") do
              h3(class: "text-sm font-semibold text-slate-800") { I18n.t("design.page_section.title") }
              span(class: "text-xs text-slate-500 data-[status=error]:text-red-600", role: "status", aria: { live: "polite" },
                   data: { "design--style-autosave-target": "status" })
            end
            render PageSectionContent.new(document_design: @document_design, paper_size_url: @urls[:paper_size],
                                          editable: @editable)
          end
        end

        private

        def section_data
          {
            page_section: true,
            controller: "design--style-autosave",
            action: ACTIONS,
            "design--style-autosave-field-url-value": @urls[:field],
            "design--style-autosave-preview-url-value": @urls[:preview],
            "design--style-autosave-field-prefix-value": "page",
            "design--style-autosave-panel-target-value": PageSectionContent::TARGET,
            "design--style-autosave-required-fields-value": REQUIRED_FIELDS.to_json,
            "design--style-autosave-saving-text-value": I18n.t("design.style_panel.status.saving"),
            "design--style-autosave-saved-text-value": I18n.t("design.style_panel.status.saved"),
            "design--style-autosave-error-text-value": I18n.t("design.style_panel.status.error")
          }
        end
      end
    end
  end
end
