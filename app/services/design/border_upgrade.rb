module Design
  # The one-off D5 data step, shared by the hosts' ReplaceDesignBorderFields
  # migrations and by the importers (a .book_design written before D5).
  #
  # Each paragraph-style row's old five border fields are resolved through its
  # chain (theme base → chapter on the same paper size → doc type), converted
  # to the twelve (LegacyBorder) and written; the D2a normaliser then turns
  # everything equal to its parent back into inherit. So every row resolves
  # exactly as before (except `large` → `full`), overrides stay on the rows
  # that had them, and overridden_fields moves from the old names to the new
  # fields still set, so they stay pushable.
  #
  # Two harmless side effects. A side with no line stores no colour (the
  # converter writes nil when nothing is drawn), so afterwards it may resolve
  # to its parent's colour; nothing is drawn there, so nothing renders
  # differently. And the normaliser compacts every style field, not only the
  # border ones (the D2a rule, spec decision 8): a doc-type value that has come
  # to equal its parent since D2a is unpinned too, and resolves the same.
  #
  # DB work only, safe inside a caller's transaction; the caller re-exports.
  module BorderUpgrade
    module_function

    # { row_id => { "border_thickness" => …, … } } from the old columns (the
    # model no longer knows them).
    def legacy_values(connection = Design::ApplicationRecord.connection)
      cols = LegacyBorder::OLD_FIELDS
      connection.select_rows("SELECT id, #{cols.join(', ')} FROM design_paragraph_styles").to_h do |id, *values|
        [ id.to_i, cols.zip(values).to_h ]
      end
    end

    # Rewrite `theme`'s rows from `legacy` (row id → old five; a row missing
    # from it has no old values of its own).
    def rewrite!(theme, legacy)
      base = theme.base_paragraph_styles.index_by(&:name)
      base.each_value { |row| write(row, [ legacy[row.id] ]) }
      theme.document_designs.includes(:paragraph_styles, :paper_size).find_each do |dd|
        chapter = dd.doc_type == "chapter" ? nil : dd.paper_size.document_designs.find_by(doc_type: "chapter")
        chapter_rows = chapter ? chapter.paragraph_styles.index_by(&:name) : {}
        dd.paragraph_styles.each do |row|
          layers = [ legacy[base[row.name]&.id] ]
          layers << legacy[chapter_rows[row.name]&.id] if chapter
          layers << legacy[row.id]
          write(row, layers)
        end
      end
      ParagraphStyleNormalizer.compact!(theme)
      carry_marks!(theme)
    end

    # A row whose whole chain has no old border value is left alone (all
    # twelve nil = inherit / no line / square): writing 0s and "none" there
    # would store noise the normaliser can't clear on a parentless row.
    def write(row, layers)
      old = LegacyBorder.overlay(layers.compact)
      return if old.values.all?(&:nil?)
      row.update_columns(LegacyBorder.convert(old))
    end

    # A row that marked any old border field now marks the new fields it
    # still stores (after the normaliser cleared the inherited ones).
    def carry_marks!(theme)
      ParagraphStyle.where(styleable: theme.document_designs).find_each do |row|
        marked = Array(row.overridden_fields)
        next unless marked.intersect?(LegacyBorder::OLD_FIELDS)
        stored = ParagraphStyle::BORDER_FIELDS.select { |f| !row[f].nil? }
        row.update_columns(overridden_fields: (marked - LegacyBorder::OLD_FIELDS) | stored)
      end
    end
  end
end
