require "test_helper"

class Design::TableStylePreviewServiceTest < ActiveSupport::TestCase
  setup do
    @was = Design.config.designcraft
    @theme = Design::Theme.create!(name: "TSPS #{SecureRandom.hex(3)}", locale: "ko")
    @ts = @theme.table_styles.find_by(name: "grid")
  end

  teardown do
    Design.config.designcraft = @was
  end

  def assert_jpeg(blob)
    assert blob.is_a?(String) && blob.bytesize > 1000, "blob too small: #{blob&.bytesize.inspect}"
    assert_equal "\xFF\xD8".b, blob.byteslice(0, 2), "not a JPEG (missing SOI marker)"
  end

  test "renders a non-empty JPEG blob for a table style" do
    Design.config.designcraft = false
    assert_jpeg Design::TableStylePreviewService.call(@theme, @ts)
  end

  test "with DesignCraft on, DesignCraft draws the sample in the table style" do
    begin
      require "designcraft_rb"
      DesignCraftRb::Client.find_cli
    rescue LoadError, DesignCraftRb::CliNotFound => e
      skip e.message
    end
    Design.config.designcraft = true

    test = self
    Design::SingleTablePdf.singleton_class.alias_method(:write_was, :write)
    Design::SingleTablePdf.define_singleton_method(:write) { |*, **| test.flunk "drawn by SingleTablePdf, not DesignCraft" }

    @theme.table_styles.each { |ts| assert_jpeg Design::TableStylePreviewService.call(@theme, ts) }
  ensure
    if Design::SingleTablePdf.respond_to?(:write_was)
      Design::SingleTablePdf.singleton_class.alias_method(:write, :write_was)
      Design::SingleTablePdf.singleton_class.remove_method(:write_was)
    end
  end

  test "when DesignCraft can't, SingleTablePdf draws it" do
    Design.config.designcraft = true
    service = Design::TableStylePreviewService.new(@theme, @ts)
    service.define_singleton_method(:designcraft_table) { |*| nil }

    assert_jpeg service.call
  end
end
