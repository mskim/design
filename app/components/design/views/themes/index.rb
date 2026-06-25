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
                div(class: "flex items-center gap-4") do
                  # The cross-theme style browser lists every paragraph style in
                  # every theme — an authoring-host inspection tool. Consumer hosts
                  # (book_write) edit styles scoped to a document design, so it's
                  # hidden there (and the route is gated too).
                  if Design.authoring?
                    a(href: helpers.style_browser_path, class: "text-sm font-medium text-blue-600 hover:underline") { I18n.t("design.style_browser.nav_link") }
                  end
                  # From-scratch theme creation is an authoring-host tool only. On
                  # consumer hosts (book_write) a blank theme has no styles and is
                  # useless — the sanctioned path is to clone an existing theme, so
                  # the per-card Clone button is the only way to start a new design.
                  if Design.authoring?
                    a(href: helpers.new_theme_path) do
                      RubyUI::Button(variant: :primary) { I18n.t("design.themes.new_theme") }
                    end
                  end
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
          RubyUI::Card(class: "theme-card flex flex-col overflow-hidden hover:shadow-md transition-shadow") do
            # Box 1 — clickable thumbnail
            a(href: helpers.theme_path(theme), class: "block group") do
              if chapter_dd
                div(class: "h-72 bg-gray-50 flex items-center justify-center overflow-hidden border-b") do
                  design_preview_img(theme, default_ps, chapter_dd, img_class: "h-full object-contain") {}
                end
              end
            end
            # Box 2 — name, locale badge, and the action buttons, grouped together
            div(class: "p-4 flex flex-col gap-2") do
              div(class: "flex items-start justify-between") do
                a(href: helpers.theme_path(theme), class: "group") do
                  h3(class: "text-lg font-semibold group-hover:text-blue-600 transition-colors") { theme.name }
                end
                RubyUI::Badge(variant: :blue, size: :sm) { theme.locale.upcase }
              end
              card_actions(theme)
            end
          end
        end

        # Clone is always available (it's the read-only consumer's path to an
        # editable copy, and a quick duplicate-and-rename for designers). Rename
        # and Delete only show when the current user may edit the theme — system
        # baseline themes are read-only on consumer hosts (book_write) but
        # editable on authoring hosts (book_design), per Theme#editable_by?.
        BTN_BASE = "inline-flex w-full items-center justify-center rounded-md px-3 py-1.5 " \
                   "text-sm font-medium transition-colors whitespace-nowrap".freeze
        BTN_CLONE = "#{BTN_BASE} bg-blue-600 text-white hover:bg-blue-700".freeze
        BTN_RENAME = "#{BTN_BASE} border border-slate-300 text-slate-700 hover:bg-slate-50".freeze
        BTN_DELETE = "#{BTN_BASE} border border-red-300 text-red-600 hover:bg-red-50".freeze

        def card_actions(theme)
          editable = theme.editable_by?(Design.current_user)
          div(class: "flex flex-col gap-2") do
            clone_action(theme)
            if editable
              div(class: "flex gap-2") do
                rename_action(theme)
                delete_action(theme)
              end
            end
          end
        end

        def clone_action(theme)
          form(action: helpers.clone_theme_path(theme), method: "post",
               data: { controller: "design--name-prompt", action: "submit->design--name-prompt#confirm",
                       "prompt-label": I18n.t("design.themes.new_theme_name") }) do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: "hidden", name: "name", value: "#{theme.name} (Custom)",
                  data: { "design--name-prompt-target": "field" })
            button(type: "submit", class: BTN_CLONE) { I18n.t("design.themes.clone") }
          end
        end

        def rename_action(theme)
          form(action: helpers.theme_path(theme), method: "post", class: "flex-1",
               data: { controller: "design--name-prompt", action: "submit->design--name-prompt#confirm",
                       "prompt-label": I18n.t("design.themes.new_theme_name") }) do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: "hidden", name: "theme[name]", value: theme.name,
                  data: { "design--name-prompt-target": "field" })
            button(type: "submit", class: BTN_RENAME) { I18n.t("design.themes.rename") }
          end
        end

        def delete_action(theme)
          form(action: helpers.theme_path(theme), method: "post", class: "flex-1",
               data: { turbo_confirm: I18n.t("design.themes.delete_confirm") }) do
            input(type: "hidden", name: "_method", value: "delete")
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            button(type: "submit", class: BTN_DELETE) { I18n.t("design.themes.delete") }
          end
        end
      end
    end
  end
end
