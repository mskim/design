module Design
  module Views
    module Themes
      class Show < Design::Views::Base
        def initialize(theme:, paper_sizes:, selected_paper_size:, document_designs:)
          @theme = theme
          @paper_sizes = paper_sizes
          @selected_paper_size = selected_paper_size
          @document_designs = document_designs
        end

        def view_template
          shell(title: @theme.name, action_slot: :theme_show, action_context: @theme, sidebar: nil) do
            div(class: "mx-auto max-w-5xl px-6 py-10 flex flex-col gap-6") do
              header_section
              if @selected_paper_size
                size_selector
                doc_grid
              else
                p(class: "text-sm text-slate-500") { I18n.t("design.themes.no_custom_themes") }
              end
            end
          end
        end

        private

        def header_section
          div(class: "flex items-center justify-between gap-4") do
            div(class: "flex items-center gap-3") do
              h1(class: "text-2xl font-semibold text-slate-900") { @theme.name }
              RubyUI::Badge(variant: :slate) do
                # Key off editability, not system?: an authoring host (authoring=true)
                # can edit system themes, so "Read-only" only applies when truly locked.
                @theme.editable_by?(Design.current_user) ? I18n.t("design.themes.my_theme") : I18n.t("design.themes.read_only")
              end
            end
            div(class: "flex items-center gap-3") do
              # Cloning is the read-only consumer's path to editing; an authoring host
              # edits system themes in place, so no clone button when already editable.
              clone_button if @theme.system? && !@theme.editable_by?(Design.current_user)
              if @theme.editable_by?(Design.current_user)
                a(href: helpers.edit_theme_path(@theme)) do
                  RubyUI::Button(variant: :primary) { I18n.t("design.themes.edit_theme_button") }
                end
              end
              a(href: helpers.themes_path, class: "text-sm font-medium text-blue-600 hover:underline") do
                I18n.t("design.themes.back_to_themes")
              end
            end
          end
        end

        def clone_button
          form(action: helpers.clone_theme_path(@theme), method: "post") do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: "hidden", name: "name", value: "#{@theme.name} (Custom)")
            button(type: "submit", class: "rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white") do
              I18n.t("design.themes.clone_to_my_theme")
            end
          end
        end

        def size_selector
          div(class: "flex items-center gap-2 flex-wrap") do
            span(class: "text-sm text-slate-500") { "#{I18n.t('design.themes.size_label')}:" }
            @paper_sizes.each { |ps| size_pill(ps) }
            if @theme.editable_by?(Design.current_user)
              a(href: helpers.new_theme_paper_size_path(@theme), data: { turbo_frame: "_top" },
                class: "text-sm font-medium text-blue-600 hover:underline") { "＋ #{I18n.t('design.paper_sizes.new_title')}" }
              a(href: helpers.edit_theme_paper_size_path(@theme, @selected_paper_size), data: { turbo_frame: "_top" },
                class: "text-sm font-medium text-blue-600 hover:underline") { I18n.t("design.shared.edit") }
              generate_sizes_button
            end
          end
        end

        def size_pill(ps)
          active = ps.id == @selected_paper_size.id
          a(
            href: helpers.theme_path(@theme, paper_size_id: ps.id),
            data: { turbo_frame: "doc_grid" },
            class: [ "rounded-full px-3 py-1 text-sm no-underline",
                     active ? "bg-slate-900 text-white" : "border border-slate-300 text-slate-700 hover:bg-slate-100" ].join(" ")
          ) { ps.display_name }
        end

        def generate_sizes_button
          button_to(
            I18n.t("design.themes.generate_sizes", size: @theme.default_paper_size&.display_name),
            helpers.generate_sizes_theme_path(@theme),
            method: :post, class: "text-sm text-blue-600 hover:underline",
            data: { turbo: false, confirm: I18n.t("design.themes.generate_sizes_confirm") }
          )
        end

        MATTER_SECTIONS = [
          [ :frontmatter, "design.themes.frontmatter" ],
          [ :bodymatter,  "design.themes.bodymatter" ],
          [ :rearmatter,  "design.themes.rearmatter" ]
        ].freeze

        def doc_grid
          grouped = Design::DocumentDesign.grouped_by_matter(@document_designs)
          index = 0
          turbo_frame_tag "doc_grid" do
            div(class: "flex flex-col gap-8",
                data: { controller: "design--preview-gallery", "doc-grid": true }) do
              MATTER_SECTIONS.each do |group, key|
                designs = grouped[group]
                next if designs.blank?
                matter_section(key, designs, index)
                index += designs.size
              end
            end
          end
        end

        def matter_section(key, designs, start_index)
          section do
            h3(class: "text-sm font-medium text-muted-foreground uppercase tracking-wide mb-3") do
              I18n.t(key)
            end
            div(class: "grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4") do
              designs.each_with_index { |dd, i| doc_card(dd, start_index + i) }
            end
          end
        end

        def doc_card(dd, index)
          ratio = "#{@selected_paper_size.width_mm} / #{@selected_paper_size.height_mm}"
          jpg_url = helpers.preview_jpg_theme_paper_size_document_design_path(@theme, @selected_paper_size, dd)
          label = doc_type_label(dd)
          div(class: "doc-card flex flex-col gap-1") do
            button(
              type: "button",
              class: "doc-card__open block w-full bg-white border border-slate-200 shadow-sm overflow-hidden",
              style: "aspect-ratio: #{ratio};",
              data: {
                "design--preview-gallery-target": "item",
                action: "design--preview-gallery#open",
                index: index, url: jpg_url, label: label
              }
            ) do
              design_preview_img(@theme, @selected_paper_size, dd, img_class: "w-full h-full object-contain") do
                div(class: "flex h-full w-full items-center justify-center text-xs text-slate-400") do
                  I18n.t("design.themes.no_preview")
                end
              end
            end
            div(class: "flex items-center justify-between gap-1") do
              span(class: "text-xs text-slate-600") { label }
              if @theme.editable_by?(Design.current_user)
                # Break out of the doc_grid turbo-frame — the edit page is a full-page
                # editor with no doc_grid frame, so a frame-scoped click would render
                # "Content missing" instead of navigating to the editor.
                a(href: helpers.edit_theme_paper_size_document_design_path(@theme, @selected_paper_size, dd),
                  data: { turbo_frame: "_top" },
                  class: "text-xs text-blue-600 hover:underline") { I18n.t("design.themes.edit") }
              end
            end
          end
        end

        def doc_type_label(dd)
          I18n.t("design.doc_types.#{dd.doc_type}", default: dd.doc_type)
        end
      end
    end
  end
end
