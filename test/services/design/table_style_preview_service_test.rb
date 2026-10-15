require "test_helper"

class Design::TableStylePreviewServiceTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "TSPS #{SecureRandom.hex(3)}", locale: "ko")
    @ts = @theme.table_styles.find_by(name: "grid")
  end

  def designcraft_cli!
    require "designcraft_rb"
    DesignCraftRb::Client.find_cli
  rescue LoadError, DesignCraftRb::CliNotFound => e
    skip e.message
  end

  def assert_jpeg(blob)
    assert blob.is_a?(String) && blob.bytesize > 1000, "blob too small: #{blob&.bytesize.inspect}"
    assert_equal "\xFF\xD8".b, blob.byteslice(0, 2), "not a JPEG (missing SOI marker)"
  end

  test "DesignCraft draws the sample in each table style, a JPEG" do
    designcraft_cli!
    @theme.table_styles.each { |ts| assert_jpeg Design::TableStylePreviewService.call(@theme, ts) }
  end

  test "when DesignCraft can't, the preview raises (the controller answers 422)" do
    service = Design::TableStylePreviewService.new(@theme, @ts)
    service.define_singleton_method(:designcraft_table) { |*| raise "no font" }

    assert_raises(RuntimeError) { service.call }
  end
end
