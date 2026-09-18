module Design
  class DefaultGenerator
    def self.call(paper_size) = new(paper_size).call

    def self.call_for(document_design)
      new(document_design.paper_size).generate_headings_for(document_design)
    end

    def initialize(paper_size) = @paper_size = paper_size

    def call
      fill_layout
      @paper_size.document_designs.each { |dd| generate_headings_for(dd) }   # non-chapter is a no-op
      @paper_size
    end

    MARGIN_RULE_KEYS = { "left_margin_mm" => :left, "top_margin_mm" => :top, "right_margin_mm" => :right,
                         "bottom_margin_mm" => :bottom, "binding_margin_mm" => :binding }.freeze

    # Margins and body line count from the rules, skipping fields the user (or
    # an explicit creation value) marked. update_columns skips validations and
    # callbacks, but updated_at is written too: every doc type's preview on
    # this size keys on paper_size.updated_at (PreviewService#cache_fingerprint),
    # so 기본값 다시 생성 must invalidate them.
    def fill_layout
      assigns = PaperSize::GENERATABLE_FIELDS.reject { |f| @paper_size.overridden?(f) }.index_with { |f| generated_value(f) }
      @paper_size.update_columns(assigns.merge("updated_at" => Time.current)) if assigns.any?
    end

    # The rule's value for one generatable field of this size: what
    # 기본값 다시 생성 writes and what the Page section's × returns a margin to.
    def generated_value(field)
      field = field.to_s
      return GenerationRules.body_line_count_for(@paper_size.height_mm) if field == "body_line_count"
      key = MARGIN_RULE_KEYS.fetch(field) { raise ArgumentError, "not a generatable field: #{field}" }
      GenerationRules.margins_for(@paper_size.width_mm, @paper_size.height_mm).fetch(key)
    end

    # Scaled heading sizes live on chapter only, as sparse font_size rows; every
    # other doc type on the size resolves them through chapter (theme → chapter
    # → doc type). A user-overridden font_size is left alone.
    def generate_headings_for(document_design)
      return unless document_design.doc_type == "chapter"
      theme  = @paper_size.theme
      height = @paper_size.height_mm
      GenerationRules::HEADING_SCALED_STYLES.each do |name|
        base = theme.base_paragraph_styles.find_by(name: name)
        next unless base&.font_size
        row = document_design.paragraph_styles.find_or_initialize_by(name: name)
        next if row.overridden?(:font_size)
        row.font_size = GenerationRules.scaled_size(base.font_size, height)
        row.save!
      end
    end
  end
end
