module Design
  # Compacts a theme's doc-type paragraph styles so each row stores only the
  # fields that differ from its parent (theme base for chapter; theme base →
  # chapter for other doc types). Chapter is normalised first so the other doc
  # types compare against chapter's already-compacted resolution.
  #
  # Per field: "" → nil (blank never means "no value", it means inherit), then
  # a value equal to the parent → nil. Rows left empty are deleted when a parent
  # exists; parentless rows are kept. Afterwards every design of the theme is
  # touched (preview cache) and the theme .db is re-exported.
  class ParagraphStyleNormalizer
    def self.call(theme) = new(theme).call

    def initialize(theme)
      @theme = theme
    end

    def call
      Design::ApplicationRecord.transaction do
        ordered_designs.each { |dd| normalize_design(dd) }
        @theme.document_designs.update_all(updated_at: Time.current)
      end
      ThemeDbExportService.new(@theme).export!
    end

    private

    def ordered_designs
      chapters, others = @theme.document_designs.to_a.partition { |dd| dd.doc_type == "chapter" }
      chapters + others
    end

    # parent_values reads chapter rows from the DB on each call, so rows saved
    # by the chapter pass are what the other doc types compare against.
    def normalize_design(dd)
      dd.paragraph_styles.each do |row|
        parent = dd.parent_values(row.name)
        cleared = ParagraphStyle::STYLE_FIELDS.select do |f|
          !row[f].nil? && (blank_string?(row[f]) || ParagraphStyle.same_value?(f, row[f], parent[f]))
        end
        cleared.each { |f| row[f] = nil }
        row.overridden_fields = Array(row.overridden_fields) - cleared

        if ParagraphStyle::STYLE_FIELDS.all? { |f| row[f].nil? } && dd.style_has_parent?(row.name)
          row.destroy!
        elsif row.changed?
          row.save!
        end
      end
    end

    def blank_string?(value) = value.is_a?(String) && value.strip.empty?
  end
end
