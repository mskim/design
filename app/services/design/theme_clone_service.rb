module Design
  class ThemeCloneService
    # `user:` copies a theme for a designer (a custom theme, every size, named
    # "<source> (Custom)"). `book_id:` copies it into a book's own design, which
    # keeps the source's name (uniqueness is per book) and records the source;
    # `paper_size:` (a local_name) copies just that size, else the source's first.
    def initialize(source_theme, user: nil, book_id: nil, paper_size: nil, name: nil)
      @source = source_theme
      @user = user
      @book_id = book_id
      @paper_size = paper_size
      @requested_name = name
      @fell_back = false
    end

    # True when the requested paper size wasn't in the source and its first size
    # was copied instead.
    def fell_back? = @fell_back

    # Wrapped in a transaction so a mid-way failure never leaves a half-built
    # theme persisted (paper sizes / document designs / styles are created across
    # many saves, each firing seeding callbacks).
    def clone
      ActiveRecord::Base.transaction do
        new_theme = @source.dup
        new_theme.user = @user
        new_theme.book_id = @book_id
        new_theme.source_theme_id = (@source.id if @book_id)
        new_theme.imported_at = nil
        new_theme.name = @book_id ? (@requested_name.presence&.strip || @source.name) : unique_name
        new_theme.save!

        # After-create callback seeded default table_styles + table_heading_cell/
        # table_body_cell paragraph_styles on new_theme. Destroy them so the
        # source's customized rows can be copied in cleanly without uniqueness
        # collisions on (theme_id, name).
        new_theme.table_styles.destroy_all
        new_theme.base_paragraph_styles
                 .where(name: %w[table_heading_cell table_body_cell])
                 .destroy_all

        clone_base_styles(new_theme)
        clone_paper_sizes(new_theme)
        clone_table_styles(new_theme)

        # Its associations were loaded (and emptied) by the destroy_alls above; reload so callers
        # (the .db export walks them) see the copied rows.
        new_theme.reload
      end
    end

    # Copies one paper size, with its paragraph styles and its document designs
    # (their styles and heading elements), into an existing theme.
    def clone_paper_size_into(new_theme, ps)
      new_ps = ps.dup
      new_ps.theme = new_theme
      new_ps.save!

      # PaperSize after_create (DefaultGenerator) seeds default paragraph
      # styles; clear them so the source's styles copy in without
      # name-uniqueness collisions on (styleable_type, styleable_id).
      new_ps.paragraph_styles.destroy_all
      ps.paragraph_styles.each do |style|
        new_style = style.dup
        new_style.styleable = new_ps
        new_style.save!
      end

      ps.document_designs.each do |dd|
        clone_document_design(dd, new_ps)
      end

      new_ps
    end

    private

    def unique_name
      base = @requested_name.presence&.strip || "#{@source.name} (Custom)"
      name = base
      counter = 1
      while Design::Theme.where(user_id: @user&.id, name: name).exists?
        counter += 1
        name = "#{base} #{counter}"
      end
      name
    end

    def clone_base_styles(new_theme)
      @source.base_paragraph_styles.each do |style|
        new_style = style.dup
        new_style.styleable = new_theme
        new_style.save!
      end
    end

    def clone_paper_sizes(new_theme)
      selected_paper_sizes.each { |ps| clone_paper_size_into(new_theme, ps) }
    end

    # Every size when none was asked for; else the one named, or the source's
    # first (its default_paper_size) when it lacks that one. A source with no
    # sizes gives none.
    def selected_paper_sizes
      return @source.paper_sizes.to_a if @paper_size.nil?

      match = @source.paper_sizes.order(:id).find_by(local_name: @paper_size)
      return [ match ] if match

      fallback = Array(@source.default_paper_size)
      @fell_back = fallback.any?
      fallback
    end

    def clone_table_styles(new_theme)
      @source.table_styles.each do |ts|
        copy = ts.dup
        copy.theme = new_theme
        copy.save!
      end
    end

    def clone_document_design(dd, new_ps)
      new_dd = dd.dup
      new_dd.paper_size = new_ps
      new_dd.save!

      # DocumentDesign after_create (DefaultGenerator.call_for) seeds default
      # paragraph styles + heading elements; clear them before copying the
      # source's so the clone is an exact copy and names don't collide.
      new_dd.paragraph_styles.destroy_all
      new_dd.heading_elements.destroy_all

      dd.paragraph_styles.each do |style|
        new_style = style.dup
        new_style.styleable = new_dd
        new_style.save!
      end

      dd.heading_elements.each do |he|
        new_he = he.dup
        new_he.document_design = new_dd
        new_he.save!
      end
    end
  end
end
