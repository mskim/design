require "test_helper"
require "tmpdir"

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

  test "concurrent generation for the same document does not corrupt each other" do
    Design::PreviewService.new(@dd, paper_size: @ps).clear_cache
    # Release all threads at once (cache is cold) so their generations overlap.
    latch = Queue.new
    threads = 5.times.map do
      Thread.new do
        latch.pop
        Design::PreviewService.new(@dd, paper_size: @ps).generate
      end
    end
    5.times { latch << :go }
    results = threads.map(&:value)
    failures = results.reject { |r| r[:success] }
    assert_empty failures, "concurrent previews failed: #{failures.map { |r| r[:error] }.uniq.inspect}"
  end

  test "concurrent generations tolerate each other deleting the same stale pages" do
    svc = Design::PreviewService.new(@dd, paper_size: @ps)
    svc.clear_cache
    preview_dir = svc.send(:preview_dir)
    FileUtils.mkdir_p(preview_dir)
    # Pre-seed stale pages above any count the chapter can render, so every thread's
    # publish_pages finds the same files to delete; the losers must not raise ENOENT.
    stale = [ 5, 6 ].map { |n| File.join(preview_dir, "preview_#{n}.jpg") }
    stale.each { |f| File.binwrite(f, "stale") }

    # GENERATION_LOCK staggers the threads, so left alone they would reach publish_pages
    # one at a time and never race. Rendezvous after rasterizing so all 5 publish at once.
    n = 5
    barrier = Queue.new
    services = n.times.map do
      svc = Design::PreviewService.new(@dd, paper_size: @ps)
      svc.define_singleton_method(:convert_pdf_to_jpgs) do |pdf, dir|
        count = Design::PdfToJpg.convert_pages(pdf, dir, max_pages: Design::PreviewService::MAX_PREVIEW_PAGES, dpi: 72)
        barrier << :arrived
        Thread.pass until barrier.size >= n # every thread holds until the last one arrives
        count
      end
      svc
    end

    latch = Queue.new
    threads = services.map do |svc|
      Thread.new do
        latch.pop
        svc.generate
      end
    end
    n.times { latch << :go }
    results = threads.map(&:value)
    failures = results.reject { |r| r[:success] }
    assert_empty failures, "concurrent previews failed: #{failures.map { |r| r[:error] }.uniq.inspect}"
    stale.each { |f| refute File.exist?(f), "stale #{File.basename(f)} should have been removed" }
  end

  test "a chapter renders more than one page, capped at MAX_PREVIEW_PAGES, with per-page overlays" do
    result = Design::PreviewService.new(@dd, paper_size: @ps).generate
    assert result[:success], result[:error]
    assert_operator result[:page_count], :>=, 2, "chapter sample should span 2+ pages"
    assert_operator result[:page_count], :<=, Design::PreviewService::MAX_PREVIEW_PAGES
    assert_equal result[:page_count], result[:pages].size
    result[:pages].each_with_index do |pg, i|
      assert File.exist?(pg[:jpg_path]), "missing page #{i + 1} jpg"
      assert_match(/preview_#{i + 1}\.jpg\z/, pg[:jpg_path])
    end
    assert result[:pages][1][:overlay_data].any? { |o| o[:type] == "paragraph" }, "page 2 should have paragraph overlays"
    # page-1 aliases keep old callers working
    assert_equal result[:pages][0][:jpg_path], result[:jpg_path]
    assert_equal result[:pages][0][:overlay_data], result[:overlay_data]
  end

  test "a title page renders exactly one page" do
    dd = @ps.document_designs.create!(doc_type: "title_page")
    result = Design::PreviewService.new(dd, paper_size: @ps).generate
    assert result[:success], result[:error]
    assert_equal 1, result[:page_count]
  ensure
    Design::PreviewService.new(dd, paper_size: @ps).clear_cache rescue nil
  end

  test "cache hit returns the same page structure and needs every page file" do
    svc = Design::PreviewService.new(@dd, paper_size: @ps)
    first = svc.generate
    cached = Design::PreviewService.new(@dd, paper_size: @ps).generate
    assert_equal first[:page_count], cached[:page_count]
    assert_equal first[:pages].map { |p| p[:jpg_path] }, cached[:pages].map { |p| p[:jpg_path] }
    File.delete(first[:pages].last[:jpg_path])
    regenerated = Design::PreviewService.new(@dd, paper_size: @ps).generate
    assert File.exist?(first[:pages].last[:jpg_path]), "a missing page file must force regeneration"
    assert regenerated[:success]
  end

  test "page background is painted on page 2 as well" do
    @dd.update!(page_bg_color: "#ffeeaa")
    svc = Design::PreviewService.new(@dd, paper_size: @ps)
    svc.clear_cache
    # generate removes its work dir in `ensure`, so capture the finished PDF's bytes
    # from inside the rasterize step (a singleton override is more explicit than minitest/mock's stub here).
    captured = nil
    svc.define_singleton_method(:convert_pdf_to_jpgs) do |pdf, dir|
      captured = File.binread(pdf)
      Design::PdfToJpg.convert_pages(pdf, dir, max_pages: Design::PreviewService::MAX_PREVIEW_PAGES, dpi: 72)
    end
    result = svc.generate
    assert result[:success], result[:error]
    assert captured, "rasterize step was not reached"

    require "hexapdf"
    require "stringio"
    doc = HexaPDF::Document.new(io: StringIO.new(captured))
    assert_operator doc.pages.count, :>=, 2
    bleed = "#{-Design::PreviewService::BLEED_PT} #{-Design::PreviewService::BLEED_PT} "
    assert_includes doc.pages[0].contents, bleed, "page 1 bleed rect (known-good today)"
    assert_includes doc.pages[1].contents, bleed, "page 2 should carry the same background bleed rect"
  end

  test "editing the sample content invalidates the preview cache" do
    Dir.mktmpdir do |dir|
      Design.config.sample_content_dir = dir
      svc = Design::PreviewService.new(@dd, paper_size: @ps)
      first = svc.generate
      mtime = File.mtime(first[:jpg_path])
      sleep 0.05
      Design::SampleContent.for(doc_type: "chapter", locale: "ko").save("# [chapter] 편집\n\n짧은 본문.\n")
      again = Design::PreviewService.new(@dd, paper_size: @ps).generate
      assert again[:success], again[:error]
      refute_equal mtime, File.mtime(again[:jpg_path]), "preview should regenerate after a content edit"
    end
  end
end
