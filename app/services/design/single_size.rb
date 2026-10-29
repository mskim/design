module Design
  # A design has one paper size. Collapses a theme from before that to its
  # default (first) size; with split: true each other size first becomes a
  # design of its own ("<name> <size>", same owner and language), copied with
  # its own document designs and styles. Exports every changed theme's .db.
  #
  # Usage:
  #   Design::SingleSize.plan(theme, split: true)   # => what collapse! would do, or nil
  #   Design::SingleSize.collapse!(theme, split: true)
  module SingleSize
    Plan = Data.define(:theme, :kept, :removed, :split_names) do
      def to_s
        line = "#{theme.name} (##{theme.id}): keep #{label(kept)}, remove #{removed.map { label(_1) }.join(", ")}"
        split_names.any? ? "#{line}; new designs #{split_names.join(", ")}" : line
      end

      private

      def label(ps) = ps.local_name.presence || ps.size_name
    end

    module_function

    # nil when the theme already has one size (or none).
    def plan(theme, split: false)
      kept, *removed = theme.paper_sizes.order(:id).to_a
      return if removed.empty?

      names = split ? removed.map { |ps| split_name(theme, ps) } : []
      Plan.new(theme:, kept:, removed:, split_names: names)
    end

    # Returns the plan carried out (nil when there was nothing to do).
    def collapse!(theme, split: false)
      plan = plan(theme, split:) or return

      copies = ActiveRecord::Base.transaction do
        made = split ? plan.removed.map { |ps| copy_size(theme, ps) } : []
        plan.removed.each(&:destroy!)
        made
      end
      ([ theme.reload ] + copies).each { |t| ThemeDbExportService.new(t).export! }
      plan
    end

    def copy_size(theme, ps)
      ThemeCloneService.new(theme, user: theme.user, paper_size: ps, name: split_name(theme, ps)).clone
    end

    def split_name(theme, ps) = "#{theme.name} #{ps.name_label(theme.locale)}"
  end
end
