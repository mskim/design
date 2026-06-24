require "test_helper"

class Design::TableStyleResolverTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "TSR #{SecureRandom.hex(3)}", locale: "ko")
    @ts = @theme.table_styles.find_by(name: "grid")
  end

  test "resolves a style hash with CMYK colors and required keys" do
    hash = Design::TableStyleResolver.call(@theme, @ts)

    assert_equal @ts.name, hash[:name]
    assert_kind_of Float, hash[:border_width]
    assert_equal :full, hash[:border_style] if @ts.border_style.nil?
    # colors are converted to CMYK arrays (or nil when the source color is blank)
    [ :border_color, :header_background, :header_text_color,
      :alternate_row_background, :body_text_color ].each do |key|
      val = hash[key]
      assert(val.nil? || (val.is_a?(Array) && val.size == 4), "#{key} not a CMYK array: #{val.inspect}")
    end
    assert_nil hash[:body_background]
  end

  test "includes header and body cell paragraph hashes from the theme" do
    hash = Design::TableStyleResolver.call(@theme, @ts)
    assert hash.key?(:header_cell_paragraph_style)
    assert hash.key?(:body_cell_paragraph_style)
    # seeded theme has the cell paragraph styles, so these resolve to hashes
    assert_kind_of Hash, hash[:header_cell_paragraph_style]
    assert hash[:header_cell_paragraph_style].key?(:font_size)
  end
end
