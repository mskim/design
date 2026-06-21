module Design
  class SampleContent
    CONTENT_DIR = Design::Engine.root.join("db", "sample_content")

    attr_reader :doc_type, :locale, :raw

    def initialize(doc_type:, locale:)
      @doc_type = doc_type
      @locale = locale
      @raw = read_file
    end

    def self.for(doc_type:, locale:)
      content = new(doc_type: doc_type, locale: locale)
      content.exists? ? content : new(doc_type: doc_type, locale: "ko")
    end

    def exists?
      raw.present?
    end

    def heading?
      raw&.match?(/\A```heading/)
    end

    def heading_hash
      return {} unless heading?

      yaml_str = raw.match(/```heading\s*\n---\n(.+?)---\s*\n```/m)&.captures&.first
      return {} unless yaml_str

      YAML.safe_load(yaml_str, symbolize_names: true) || {}
    end

    TEMPLATE_PLACEHOLDERS = {
      "author" => "홍길동",
      "publisher" => "북치고출판사"
    }.freeze

    def body_paragraphs
      return [] if heading? || raw.blank?

      lines = raw.strip.lines
      # Skip the # [doc_type] Title line if present
      lines.shift if lines.first&.match?(/\A#\s+\[/)
      text = lines.join.strip
      text = interpolate_templates(text)
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

    def read_file
      path = CONTENT_DIR.join(locale, "#{doc_type}.md")
      path.exist? ? path.read : nil
    end
  end
end
