require "test_helper"

class Design::PreviewServiceLiveTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "LV #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  teardown do
    Design::PreviewService.new(@dd, paper_size: @ps).clear_cache
  end

  test "a live render gets its own token folder, writes no cache stamp and is never served from cache" do
    a = Design::PreviewService.new(@dd, paper_size: @ps, live: true).generate
    b = Design::PreviewService.new(@dd, paper_size: @ps, live: true).generate
    assert_match Design::PreviewService::LIVE_TOKEN, a[:live_token]
    refute_equal a[:live_token], b[:live_token]
    assert_equal Design::PreviewService.live_jpg_path(@dd.id, a[:live_token], 1), a[:jpg_path].to_s
    refute File.exist?(File.join(File.dirname(a[:jpg_path]), "cache_stamp.json"))
    assert_nil Design::PreviewService.new(@dd, paper_size: @ps).generate[:live_token], "a saved render has no token"
  end

  test "older live folders are pruned; recent ones are kept" do
    old = Design::PreviewService.new(@dd, paper_size: @ps, live: true).generate
    recent = Design::PreviewService.new(@dd, paper_size: @ps, live: true).generate
    old_dir = File.dirname(old[:jpg_path])
    File.utime(1.hour.ago.to_time, 1.hour.ago.to_time, old_dir)

    Design::PreviewService.new(@dd, paper_size: @ps, live: true).generate

    refute Dir.exist?(old_dir)
    assert Dir.exist?(File.dirname(recent[:jpg_path]))
  end

  test "live_jpg_path accepts only a 16-hex token and a positive page" do
    assert Design::PreviewService.live_jpg_path(@dd.id, "0123456789abcdef", 2).end_with?("live/0123456789abcdef/preview_2.jpg")
    assert_nil Design::PreviewService.live_jpg_path(@dd.id, "../../etc", 1)
    assert_nil Design::PreviewService.live_jpg_path(@dd.id, "0123456789ABCDEF", 1)
    assert_nil Design::PreviewService.live_jpg_path(@dd.id, "0123456789abcdef", 0)
  end
end
