module Design
  module Views
    module ParagraphStyles
      # Full-page form for a theme base style or a paper-size style. Doc-type
      # styles are edited in the studio Panel instead.
      class Form < Design::Views::Base
        # theme: is required — every sidebar branch dereferences it.
        def initialize(paragraph_style:, theme:, form_url:, cancel_url:, crumbs:, paper_size: nil)
          @paragraph_style = paragraph_style
          @form_url = form_url
          @cancel_url = cancel_url
          @crumbs = crumbs
          @paper_size = paper_size
          @theme = theme
        end

        def view_template
          shell(title: @paragraph_style.name, action_slot: nil, sidebar: sidebar) do
            div(class: "px-6 py-8 flex flex-col gap-8") do
              render Design::Views::Breadcrumb.new(crumbs: @crumbs)

              h1(class: "text-2xl font-semibold text-slate-900") { @paragraph_style.name }

              div(class: "flex flex-col lg:flex-row gap-6") do
                div(class: "flex-1 min-w-0") { form_section }
              end
            end
          end
        end

        private

        # Two callers, two rail contexts:
        #   base/size-level (theme+size) → highlight size settings, same-named style switch
        #   theme-level (theme only)     → rail at the default size, nothing highlighted
        def sidebar
          if @paper_size
            theme_sidebar(@theme, @paper_size, current: { kind: :paper_size }, size_url: base_style_size_url)
          else
            theme_sidebar(@theme, @theme.default_paper_size)
          end
        end

        def base_style_size_url
          lambda do |ps|
            other = ps.paragraph_styles.find_by(name: @paragraph_style.name)
            other ? helpers.edit_theme_paper_size_base_paragraph_style_path(@theme, ps, other)
                  : helpers.edit_theme_paper_size_path(@theme, ps)
          end
        end

        def form_section
          form(action: @form_url, method: "post", class: "flex flex-col gap-6") do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

            render Design::Views::ParagraphStyles::Fields.new(paragraph_style: @paragraph_style)

            div(class: "flex items-center gap-3") do
              button(
                type: "submit",
                class: "inline-flex items-center rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700"
              ) { I18n.t("design.shared.save") }
              a(
                href: @cancel_url,
                class: "text-sm font-medium text-blue-600 hover:underline"
              ) { I18n.t("design.shared.cancel") }
            end
          end
        end
      end
    end
  end
end
