module Design
  module Views
    # Which book-tree (sidebar) matter groups are open — a per-browser view
    # preference kept in a cookie by the design--book-tree controller, so the
    # server renders the tree and the theme page grid with no flash. The value
    # is the open matter keys, comma-separated ("frontmatter,bodymatter").
    module BookTree
      COOKIE  = "design_tree_open"
      KEYS    = %w[cover frontmatter bodymatter rearmatter other].freeze
      DEFAULT = %w[bodymatter].freeze

      # nil (no cookie) → DEFAULT; "" → nothing open (the user closed every group);
      # unknown keys are dropped, and a cookie with no known key at all → DEFAULT.
      def self.open_keys(raw)
        return DEFAULT if raw.nil?
        tokens = raw.to_s.split(",").map(&:strip).reject(&:empty?)
        return [] if tokens.empty?
        known = tokens.uniq & KEYS
        known.empty? ? DEFAULT : known
      end
    end
  end
end
