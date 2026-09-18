module Design
  # Sample text used by previews, one Markdown file per (locale, doc_type). Resolution:
  # the host's Design.config.sample_content_dir first (editable), then the gem's bundled
  # files (read-only fallback). Saves only ever write under the host dir.
  class SampleContent
    GEM_CONTENT_DIR = Design::Engine.root.join("db", "sample_content")
    # Types whose sample is a ```heading YAML block instead of Markdown body text.
    HEADING_TYPES = %w[title_page inside_cover part_cover document_cover].freeze
    TOC_ROW = /\A##\s+\d+:.+:\d+\s*\z/
    HEADING_BLOCK = /\A```heading\s*\n---\n(.+?)---\s*\n```/m

    class InvalidContent < StandardError; end

    attr_reader :doc_type, :locale, :raw

    def initialize(doc_type:, locale:)
      @doc_type = doc_type
      @locale = locale
      @path = resolve_path
      @raw = @path&.read
    end

    def self.for(doc_type:, locale:)
      content = new(doc_type: doc_type, locale: locale)
      content.exists? ? content : new(doc_type: doc_type, locale: "ko")
    end

    def self.host_dir = Pathname(Design.config.sample_content_dir)

    def host_path = self.class.host_dir.join(locale, "#{doc_type}.md")
    def gem_path  = GEM_CONTENT_DIR.join(locale, "#{doc_type}.md")

    def exists? = raw.present?
    def host_file? = @path == host_path && host_path.exist?

    # Cache-key ingredient: which file is in use, and its mtime/size.
    def fingerprint
      return "none" unless @path
      "#{@path}:#{@path.mtime.to_i}:#{@path.size}"
    end

    def save(text)
      self.class.validate!(doc_type, text)
      host_path.dirname.mkpath
      host_path.write(text)
      @path = host_path
      @raw = text
    end

    def restore_default!
      host_path.delete if host_path.exist?
      @path = resolve_path
      @raw = @path&.read
    end

    def self.validate!(doc_type, text)
      raise InvalidContent, I18n.t("design.sample_contents.errors.blank") if text.to_s.strip.empty?
      if HEADING_TYPES.include?(doc_type)
        yaml = text.match(HEADING_BLOCK)&.captures&.first
        raise InvalidContent, I18n.t("design.sample_contents.errors.heading") unless yaml
        begin
          YAML.safe_load(yaml)
        rescue Psych::SyntaxError => e
          raise InvalidContent, I18n.t("design.sample_contents.errors.yaml", message: e.message)
        end
      elsif doc_type == "toc"
        rows = text.lines.map(&:strip).reject { |l| l.empty? || l.start_with?("# ") }
        bad = rows.reject { |l| l.match?(TOC_ROW) }
        raise InvalidContent, I18n.t("design.sample_contents.errors.toc", line: bad.first) if bad.any?
      end
      true
    end

    def heading? = raw&.match?(/\A```heading/)

    def heading_hash
      return {} unless heading?
      yaml_str = raw.match(HEADING_BLOCK)&.captures&.first
      return {} unless yaml_str
      YAML.safe_load(yaml_str, symbolize_names: true) || {}
    end

    TEMPLATE_PLACEHOLDERS = { "author" => "홍길동", "publisher" => "북치고출판사" }.freeze

    def body_paragraphs
      return [] if heading? || raw.blank?
      lines = raw.strip.lines
      lines.shift if lines.first&.match?(/\A#\s+\[/) # drop the "# [doc_type] Title" line
      text = interpolate_templates(lines.join.strip)
      text.split(/\n\n+/).reject(&:blank?)
    end

    def title
      if heading?
        heading_hash[:title]
      else
        match = raw&.match(/\A#\s+\[\w+\]\s*(.+)/)
        match ? match[1].strip : doc_type.titleize
      end
    end

    private

    def interpolate_templates(text)
      text.gsub(/<%=\s*(\w+)\s*%>/) { TEMPLATE_PLACEHOLDERS[$1] || $1 }
    end

    def resolve_path
      [ host_path, gem_path ].find(&:exist?)
    end
  end
end
