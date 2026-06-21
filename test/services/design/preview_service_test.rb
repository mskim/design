require "test_helper"

class Design::PreviewServiceTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "Preview #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  teardown { Design::PreviewService.new(@dd, paper_size: @ps).clear_cache rescue nil }

  test "generate renders a JPG and overlay zones for a chapter" do
    result = Design::PreviewService.new(@dd, paper_size: @ps).generate
    assert result[:success], "preview failed: #{result[:error]}"
    assert File.exist?(result[:jpg_path]), "no jpg at #{result[:jpg_path]}"
    assert File.size(result[:jpg_path]) > 1000
    assert result[:page_width].to_f > 0
    assert result[:overlay_data].is_a?(Array)
  end

  test "second generate reuses cache" do
    svc = Design::PreviewService.new(@dd, paper_size: @ps)
    svc.generate
    mtime = File.mtime(svc.jpg_path)
    sleep 0.05
    Design::PreviewService.new(@dd, paper_size: @ps).generate   # fingerprint unchanged → cache hit
    assert_equal mtime, File.mtime(svc.jpg_path)
  end
end
