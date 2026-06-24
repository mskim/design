module Design
  module Views
    module Themes
      class Index < Design::Views::Base
        def initialize(themes:)
          @themes = themes
        end

        def view_template
          shell(title: I18n.t("design.themes.index_title"), action_slot: :themes_index, sidebar: nil) do
            div(class: "themes-index mx-auto max-w-7xl px-6 py-10") do
              div(class: "flex items-center justify-between mb-6") do
                h1(class: "text-2xl font-semibold") { I18n.t("design.themes.index_title") }
                a(href: helpers.new_theme_path) do
                  RubyUI::Button(variant: :primary) { I18n.t("design.themes.new_theme") }
                end
              end
              div(class: "themes-grid grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4") do
                @themes.each { |t| theme_card(t) }
              end
            end
          end
        end

        private

        def theme_card(theme)
          default_ps = theme.default_paper_size
          chapter_dd = default_ps&.document_designs&.find_by(doc_type: "chapter")
          a(href: helpers.theme_path(theme), class: "theme-card block group") do
            RubyUI::Card(class: "overflow-hidden hover:shadow-md transition-shadow") do
              if chapter_dd
                div(class: "h-40 bg-gray-50 flex items-center justify-center overflow-hidden border-b") do
                  design_preview_img(theme, default_ps, chapter_dd, img_class: "h-full object-contain") {}
                end
              end
              div(class: "p-4") do
                div(class: "flex items-start justify-between mb-2") do
                  div do
                    h3(class: "text-lg font-semibold group-hover:text-blue-600 transition-colors") { theme.name }
                    p(class: "text-sm text-muted-foreground") { theme.base_body_font }
                  end
                  RubyUI::Badge(variant: :blue, size: :sm) { theme.locale.upcase }
                end
                paper_size_badges(theme, default_ps)
                div(class: "flex items-center gap-3 text-xs text-muted-foreground mt-2") do
                  span { I18n.t("design.themes.sizes_count", count: theme.paper_sizes.count) }
                  span { I18n.t("design.themes.doc_types_count", count: theme.document_designs.count) }
                end
              end
            end
          end
        end

        def paper_size_badges(theme, default_ps)
          return unless theme.paper_sizes.any?
          div(class: "flex flex-wrap gap-1.5 mt-2") do
            theme.paper_sizes.order(:id).each do |ps|
              is_default = default_ps && ps.id == default_ps.id
              RubyUI::Badge(variant: is_default ? :blue : :slate, size: :sm) do
                lbl = ps.local_name.presence || ps.size_name
                is_default ? "#{lbl} ★" : lbl
              end
            end
          end
        end
      end
    end
  end
end
