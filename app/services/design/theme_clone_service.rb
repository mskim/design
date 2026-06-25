module Design
  class ThemeCloneService
    def initialize(source_theme, user:, name: nil)
      @source = source_theme
      @user = user
      @requested_name = name
    end

    # Wrapped in a transaction so a mid-way failure never leaves a half-built
    # theme persisted (paper sizes / document designs / styles are created across
    # many saves, each firing seeding callbacks).
    def clone
      ActiveRecord::Base.transaction do
        new_theme = @source.dup
        new_theme.user = @user
        new_theme.name = unique_name
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

        new_theme
      end
    end

    private

    def unique_name
      base = @requested_name.presence&.strip || "#{@source.name} (Custom)"
      name = base
      counter = 1
      while Design::Theme.where(user_id: @user.id, name: name).exists?
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
      @source.paper_sizes.each do |ps|
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
      end
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
