module Design
  module Views
    module SizeCopies
      # "Copy for another size": a standard size or a typed width × height
      # (the typed size wins when both are given), and an optional name.
      class Form < Design::Views::Base
        FIELD_CLASS = "w-full rounded-md border border-input bg-background px-3 py-2 text-sm".freeze

        # values: the submitted size_copy params, kept on a re-render.
        def initialize(theme:, values: {}, error: nil)
          @theme = theme
          @values = values.to_h.with_indifferent_access
          @error = error
        end

        def view_template
          title = I18n.t("design.size_copies.new_title")
          shell(title: title, sidebar: theme_sidebar(@theme, @theme.default_paper_size)) do
            div(class: "max-w-2xl mx-auto p-8 flex flex-col gap-6") do
              render Design::Views::Breadcrumb.new(crumbs: [ [ @theme.name, helpers.theme_path(@theme) ], [ title, nil ] ])
              h1(class: "text-2xl font-semibold text-slate-900") { title }
              p(class: "text-sm text-slate-600") { intro }
              render_error
              render_form
            end
          end
        end

        private

        def intro
          current = @theme.default_paper_size
          I18n.t("design.size_copies.intro", name: @theme.name, size: current ? current.display_name : "—")
        end

        def render_form
          form(action: helpers.theme_size_copy_path(@theme), method: "post", class: "space-y-6") do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

            section(I18n.t("design.size_copies.standard_size")) do
              select(name: "size_copy[size]", class: FIELD_CLASS) do
                option(value: "") { I18n.t("design.size_copies.choose_placeholder") }
                Design::PaperSize::STANDARD_SIZES.each do |s|
                  option(value: s[:local_name], selected: s[:local_name] == selected_size) { size_label(s) }
                end
              end
            end

            section(I18n.t("design.size_copies.custom_size")) do
              p(class: "text-sm text-slate-600") { I18n.t("design.size_copies.custom_hint") }
              div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
                number_field(I18n.t("design.size_copies.width"), :width_mm)
                number_field(I18n.t("design.size_copies.height"), :height_mm)
              end
            end

            section(I18n.t("design.size_copies.name_label")) do
              input(type: "text", name: "size_copy[name]", value: @values[:name].to_s, class: FIELD_CLASS,
                    placeholder: I18n.t("design.size_copies.name_hint", name: @theme.name))
            end

            div(class: "flex gap-3") do
              render RubyUI::Button.new(variant: :primary, type: :submit) { I18n.t("design.size_copies.create_button") }
              a(href: helpers.theme_path(@theme)) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.shared.cancel") } }
            end
          end
        end

        # The submitted size, else the first standard size other than this design's.
        def selected_size
          return @values[:size] if @values.key?(:size)
          current = @theme.default_paper_size
          other = Design::PaperSize::STANDARD_SIZES.find do |s|
            !current || [ s[:width_mm], s[:height_mm] ] != [ current.width_mm.to_i, current.height_mm.to_i ]
          end
          other&.dig(:local_name)
        end

        # "사륙판 (128×188 mm)"
        def size_label(s) = "#{s[:local_name]} (#{s[:width_mm]}×#{s[:height_mm]} mm)"

        def section(title)
          div(class: "space-y-3") do
            h3(class: "text-lg font-medium border-b pb-2") { title }
            yield
          end
        end

        def number_field(label_text, attr)
          render Design::Views::Inputs::NumberField.new(
            name: "size_copy[#{attr}]", value: @values[attr].to_s, label: label_text,
            unit: :mm, step: 1.0, min: 0, layout: :stacked)
        end

        # The gem has NO RubyUI::Alert — plain div.
        def render_error
          return unless @error
          div(class: "rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-700") { @error }
        end
      end
    end
  end
end
