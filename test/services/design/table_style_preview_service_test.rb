require "test_helper"

class Design::TableStylePreviewServiceTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "TSPS #{SecureRandom.hex(3)}", locale: "ko")
    @ts = @theme.table_styles.find_by(name: "grid")
  end

  test "renders a non-empty JPEG blob for a table style" do
    blob = Design::TableStylePreviewService.call(@theme, @ts)
    assert blob.is_a?(String) && blob.bytesize > 1000, "blob too small: #{blob&.bytesize.inspect}"
    assert_equal "\xFF\xD8".b, blob.byteslice(0, 2), "not a JPEG (missing SOI marker)"
  end
end
