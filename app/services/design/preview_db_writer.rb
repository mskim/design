module Design
  # PreviewService's populate methods writing a preview into a doc_processor_rb DB, for
  # doc_processor_rb to lay out (DesignCraft off, or when it fails). DesignCraftRb::UnitRows takes
  # the same calls and keeps the rows for DesignCraft without a DB; this goes when
  # doc_processor_rb no longer lays previews out.
  class PreviewDbWriter
    def initialize(db_doc)
      @db_doc = db_doc
      @db = db_doc.instance_variable_get(:@db)
      db_doc.document_info # a fresh DB has its documents row (id 1) once it is first read
    end

    # Columns an older DB lacks (page_bg_color) are left out.
    def update_document(**attrs) = @db[:documents].where(id: 1).update(attrs.slice(*@db[:documents].columns))
    def update_master(**attrs) = @db_doc.master_page.update(attrs)
    def clear_styles = @db[:paragraph_styles].delete

    def add_style(name:, attributes:, display_name: name)
      DocProcessorRb::Database::Models::ParagraphStyle.create(name: name, display_name: display_name, attributes: attributes)
    end

    def delete_style(name) = @db[:paragraph_styles].where(name: name).delete

    def add_slot(**attrs)
      @db[:header_footer_slots].insert(document_id: 1, **attrs) if @db.table_exists?(:header_footer_slots)
    end

    def add_heading_item(type, content)
      DocProcessorRb::Database::Models::HeadingItem.create(document_id: 1, item_type: type, item_content: content)
    end

    def add_toc_item(**attrs) = DocProcessorRb::Database::Models::TocItem.create(document_id: 1, **attrs)

    # A block; with columns of its own (a wing's component and markup) written as that row.
    def add_block(sequence:, content:, block_type: "body", metadata: nil, **columns)
      return @db_doc.add_block(sequence: sequence, content: content, block_type: block_type, metadata: metadata) if columns.empty?

      @db[:paragraphs].insert(document_id: 1, sequence: sequence, content: content, block_type: block_type,
                              metadata: metadata.is_a?(Hash) ? metadata.to_json : metadata, **columns)
    end
  end
end
