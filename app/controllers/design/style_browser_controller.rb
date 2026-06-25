module Design
  class StyleBrowserController < Design::ApplicationController
    # The cross-theme style browser is an authoring-host inspection tool. On
    # consumer hosts (book_write) styles are edited scoped to a document design,
    # so the feature is hidden and its route redirects back to the theme list.
    before_action :require_authoring

    def index
      @themes = Design::Theme.all.order(:name)
      @selected_theme_name = params[:theme].presence
      @selected_theme = @selected_theme_name ? Design::Theme.find_by(name: @selected_theme_name) : nil
      @selected_theme_name = nil unless @selected_theme

      @size_names = build_size_names
      @selected_size_name = params[:size].presence
      @selected_size_name = nil unless @size_names.include?(@selected_size_name)

      @doc_types = build_doc_types
      @selected_doc_type = params[:doc_type].presence
      @selected_doc_type = nil unless @doc_types.include?(@selected_doc_type)

      @style_rows = build_style_rows
      @style_names = @style_rows.map { |r| r[:style].name }.uniq.sort
      @selected_style_name = params[:style_name].presence
      @selected_style_name = nil unless @style_names.include?(@selected_style_name)
      @style_rows = @style_rows.select { |r| r[:style].name == @selected_style_name } if @selected_style_name

      render Design::Views::ParagraphStyles::Browser.new(
        themes: @themes, size_names: @size_names, doc_types: @doc_types,
        style_names: @style_names, style_rows: @style_rows,
        selected_theme: @selected_theme_name, selected_size: @selected_size_name,
        selected_doc_type: @selected_doc_type, selected_style_name: @selected_style_name
      )
    end

    private

    def require_authoring
      redirect_to themes_path unless Design.authoring?
    end

    def build_size_names
      scope = Design::PaperSize.all
      scope = scope.where(theme: @selected_theme) if @selected_theme
      scope.distinct.pluck(:size_name).sort
    end

    def build_doc_types
      scope = Design::DocumentDesign.joins(:paper_size)
      scope = scope.where(design_paper_sizes: { theme_id: @selected_theme.id }) if @selected_theme
      scope = scope.where(design_paper_sizes: { size_name: @selected_size_name }) if @selected_size_name
      scope.distinct.pluck(:doc_type).sort
    end

    def filtered_designs
      scope = Design::DocumentDesign.includes(:paragraph_styles, paper_size: { theme: :base_paragraph_styles })
      if @selected_theme || @selected_size_name
        scope = scope.joins(:paper_size)
        scope = scope.where(design_paper_sizes: { theme_id: @selected_theme.id }) if @selected_theme
        scope = scope.where(design_paper_sizes: { size_name: @selected_size_name }) if @selected_size_name
      end
      scope = scope.where(doc_type: @selected_doc_type) if @selected_doc_type
      scope
    end

    def build_style_rows
      designs = filtered_designs
      rows = []
      if @selected_doc_type
        designs.each do |dd|
          override_names = Set.new(dd.paragraph_styles.map(&:name))
          dd.merged_paragraph_styles.each do |style|
            rows << row_for(style, dd, override_names.include?(style.name))
          end
        end
      else
        designs.group_by { |dd| [ dd.theme.id, dd.paper_size.id ] }.each_value do |dds|
          base_added = Set.new
          dds.each do |dd|
            override_names = Set.new(dd.paragraph_styles.map(&:name))
            dd.merged_paragraph_styles.each do |style|
              if override_names.include?(style.name)
                rows << row_for(style, dd, true)
              elsif !base_added.include?(style.name)
                base_added.add(style.name)
                rows << { style: style, theme: dd.theme, paper_size: dd.paper_size, document_design: nil, doc_type: nil, is_override: false }
              end
            end
          end
        end
      end
      rows.sort_by { |r| [ r[:theme].name, r[:paper_size].size_name, r[:doc_type].to_s, r[:style].name ] }
    end

    def row_for(style, dd, is_override)
      { style: style, theme: dd.theme, paper_size: dd.paper_size, document_design: dd, doc_type: dd.doc_type, is_override: is_override }
    end
  end
end
