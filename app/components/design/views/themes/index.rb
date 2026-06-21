module Design
  module Views
    module Themes
      class Index < Design::Views::Base
        def initialize(system_themes:, custom_themes:)
          @system_themes = system_themes
          @custom_themes = custom_themes
        end

        def view_template
          div(class: "design-studio mx-auto max-w-6xl px-6 py-10 flex flex-col gap-8") do
            header_bar
            div(class: "themes-grid grid grid-cols-1 gap-8 lg:grid-cols-2") do
              themes_column(:system, I18n.t("design.themes.system_themes"), @system_themes) { |t| system_theme_card(t) }
              themes_column(:custom, I18n.t("design.themes.custom_themes"), @custom_themes) { |t| custom_theme_card(t) }
            end
          end
        end

        private

        def header_bar
          div(class: "design-studio__header flex items-center justify-between gap-4") do
            h1(class: "text-2xl font-semibold") { I18n.t("design.themes.index_title") }
            a(href: helpers.instance_exec(&Design.config.home_url), class: "design-studio__home text-sm text-blue-600 hover:underline") do
              I18n.t("design.themes.back_to_home")
            end
          end
        end

        def themes_column(key, title, themes)
          section(class: "themes-column flex flex-col gap-3", data: { themes: key }) do
            h2(class: "text-lg font-medium") { title }
            if themes.any?
              div(class: "theme-cards grid grid-cols-2 gap-4") do
                themes.each { |theme| yield theme }
              end
            else
              p(class: "text-sm text-slate-500") { I18n.t("design.themes.no_custom_themes") }
            end
          end
        end

        def system_theme_card(theme)
          theme_card(theme) do
            a(href: helpers.theme_path(theme), class: "theme-card__view text-sm text-blue-600 hover:underline") { I18n.t("design.themes.preview") }
            clone_form(theme)
          end
        end

        def custom_theme_card(theme)
          theme_card(theme) do
            a(href: helpers.theme_path(theme), class: "theme-card__view text-sm text-blue-600 hover:underline") { I18n.t("design.themes.view") }
            rename_form(theme)
            button_to(
              I18n.t("design.themes.delete"),
              helpers.theme_path(theme),
              method: :delete,
              data: { turbo_confirm: I18n.t("design.themes.delete_confirm") },
              class: "theme-card__delete text-sm text-red-600 hover:underline"
            )
          end
        end

        def theme_card(theme)
          div(class: "theme-card flex flex-col gap-2 rounded-lg border border-slate-200 p-3",
              data: { theme_card: theme.id }) do
            chapter_preview(theme)
            div(class: "flex flex-col") do
              span(class: "theme-card__name font-medium") { theme.name }
              span(class: "theme-card__meta text-xs text-slate-500") do
                I18n.t("design.themes.meta_summary", paper_sizes: theme.paper_sizes.count, doc_types: theme.document_designs.count)
              end
            end
            div(class: "theme-card__badge") { RubyUI::Badge(variant: :slate) { theme.locale } }
            div(class: "theme-card__actions flex flex-wrap items-center gap-3") { yield }
          end
        end

        def chapter_preview(theme)
          dd = chapter_document_design(theme)
          ratio = dd ? "#{dd.paper_size.width_mm} / #{dd.paper_size.height_mm}" : "152 / 225"
          div(class: "theme-card__preview bg-white border border-slate-200 shadow-sm overflow-hidden",
              style: "aspect-ratio: #{ratio};") do
            if dd
              img(
                src: helpers.preview_jpg_theme_paper_size_document_design_path(theme, dd.paper_size, dd),
                loading: "lazy", alt: theme.name,
                class: "w-full h-full object-contain"
              )
            else
              div(class: "preview-empty flex items-center justify-center h-full text-xs text-slate-300") do
                I18n.t("design.themes.no_preview")
              end
            end
          end
        end

        def chapter_document_design(theme)
          theme.default_paper_size&.document_designs&.find_by(doc_type: "chapter")
        end

        def clone_form(theme)
          form(action: helpers.clone_theme_path(theme), method: "post", class: "theme-card__clone flex items-center gap-2") do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(
              type: "text", name: "name", value: "#{theme.name} (Custom)",
              aria: { label: I18n.t("design.themes.new_theme_name") },
              class: "rounded border border-slate-300 px-2 py-1 text-sm"
            )
            button(type: "submit", class: "text-sm font-medium text-blue-600 hover:underline") { I18n.t("design.themes.clone") }
          end
        end

        def rename_form(theme)
          form(action: helpers.theme_path(theme), method: "post", class: "theme-card__rename flex items-center gap-2") do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(
              type: "text", name: "theme[name]", value: theme.name,
              aria: { label: I18n.t("design.themes.rename") },
              class: "rounded border border-slate-300 px-2 py-1 text-sm"
            )
            button(type: "submit", class: "text-sm font-medium text-blue-600 hover:underline") { I18n.t("design.themes.rename") }
          end
        end
      end
    end
  end
end
