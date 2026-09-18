module Design
  module Views
    module SampleContents
      # Plain-textarea editor for one (locale, doc_type) sample file. Format is unchanged
      # from the bundled files; a short hint per type says what is expected.
      class Edit < Design::Views::Base
        def initialize(theme:, doc_type:, content:, text:, error: nil, return_design: nil)
          @theme = theme
          @doc_type = doc_type
          @content = content
          @text = text
          @error = error
          @return_design = return_design
        end

        def view_template
          rail_size = @return_design&.paper_size || @theme.default_paper_size
          shell(title: page_title, action_slot: nil, sidebar: theme_sidebar(@theme, rail_size)) do
            div(class: "mx-auto max-w-4xl px-6 py-10 flex flex-col gap-6") do
              render Design::Views::Breadcrumb.new(crumbs: [
                [ @theme.name, helpers.theme_path(@theme) ],
                [ doc_type_label(@doc_type), @return_design && helpers.edit_theme_paper_size_document_design_path(@theme, @return_design.paper_size, @return_design) ],
                [ I18n.t("design.sample_contents.title"), nil ]
              ])
              h1(class: "text-2xl font-semibold text-slate-900") { page_title }
              p(class: "text-sm text-slate-500") { hint }
              error_box if @error
              edit_form
              restore_form if @content.host_file?
            end
          end
        end

        private

        def page_title = "#{doc_type_label(@doc_type)} · #{I18n.t('design.sample_contents.title')}"

        def hint
          if Design::SampleContent::HEADING_TYPES.include?(@doc_type) then I18n.t("design.sample_contents.hint_heading")
          elsif @doc_type == "toc" then I18n.t("design.sample_contents.hint_toc")
          else I18n.t("design.sample_contents.hint_body")
          end
        end

        def error_box
          div(class: "rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-700") { @error }
        end

        def edit_form
          form(action: helpers.theme_sample_content_path(@theme, @doc_type), method: "post", class: "flex flex-col gap-4") do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: "hidden", name: "return_to", value: @return_design.id) if @return_design
            textarea(name: "content", rows: 30, spellcheck: "false",
                     class: "w-full rounded border border-slate-300 p-3 font-mono text-sm leading-relaxed") { @text }
            div(class: "flex items-center gap-3") do
              render RubyUI::Button.new(variant: :primary, type: :submit) { I18n.t("design.sample_contents.save") }
              a(href: cancel_url) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.sample_contents.cancel") } }
            end
          end
        end

        def restore_form
          form(action: helpers.restore_theme_sample_content_path(@theme, @doc_type), method: "post", class: "border-t border-slate-200 pt-4",
               data: { turbo_confirm: I18n.t("design.sample_contents.restore_confirm") }) do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: "hidden", name: "return_to", value: @return_design.id) if @return_design
            render RubyUI::Button.new(variant: :outline, type: :submit) { I18n.t("design.sample_contents.restore_default") }
          end
        end

        def cancel_url
          @return_design ? helpers.edit_theme_paper_size_document_design_path(@theme, @return_design.paper_size, @return_design) : helpers.theme_path(@theme)
        end
      end
    end
  end
end
