require "test_helper"
require "tmpdir"

class Design::SampleContentTest < ActiveSupport::TestCase
  test "for(chapter, ko) loads body content" do
    c = Design::SampleContent.for(doc_type: "chapter", locale: "ko")
    assert c.exists?
    assert c.body_paragraphs.any?
  end

  test "falls back to ko when locale file missing" do
    c = Design::SampleContent.for(doc_type: "chapter", locale: "zz")
    assert c.exists?   # zz absent → ko fallback
  end

  test "heading-type parses YAML heading_hash" do
    c = Design::SampleContent.for(doc_type: "title_page", locale: "ko")
    assert c.heading?
    assert c.heading_hash.key?(:title)
  end

  test "placeholders are interpolated in body" do
    c = Design::SampleContent.for(doc_type: "copyright", locale: "ko")
    refute_includes c.body_paragraphs.join("\n"), "<%="
  end

  # --- editable content (host dir first, gem files as fallback) ---

  def with_host_dir
    Dir.mktmpdir do |dir|
      Design.config.sample_content_dir = dir
      yield Pathname(dir)
    end
  end

  test "reads the host file when present, else the gem file" do
    with_host_dir do |dir|
      gem_text = Design::SampleContent.for(doc_type: "chapter", locale: "ko").raw
      assert_includes gem_text, "본문"
      dir.join("ko").mkpath
      dir.join("ko/chapter.md").write("# [chapter] 호스트\n\n호스트 본문입니다.\n")
      c = Design::SampleContent.for(doc_type: "chapter", locale: "ko")
      assert_equal [ "호스트 본문입니다." ], c.body_paragraphs
      assert c.host_file?
    end
  end

  test "save writes only under the host dir and changes the fingerprint" do
    with_host_dir do |dir|
      c = Design::SampleContent.for(doc_type: "foreword", locale: "ko")
      before = c.fingerprint
      c.save("# [foreword] 새 서문\n\n새 본문.\n")
      assert dir.join("ko/foreword.md").exist?
      refute Design::SampleContent::GEM_CONTENT_DIR.join("ko/foreword.md").read.include?("새 본문")
      after = Design::SampleContent.for(doc_type: "foreword", locale: "ko").fingerprint
      refute_equal before, after
    end
  end

  test "save normalises CRLF so heading blocks and paragraphs parse" do
    with_host_dir do
      tp = Design::SampleContent.for(doc_type: "title_page", locale: "ko")
      tp.save("```heading\r\n---\r\ntitle: 창문\r\nauthor: 홍길동\r\n---\r\n```\r\n")
      assert_equal "창문", tp.heading_hash[:title]
      assert_equal "창문", Design::SampleContent.for(doc_type: "title_page", locale: "ko").heading_hash[:title]

      body = Design::SampleContent.for(doc_type: "chapter", locale: "ko")
      body.save("# [chapter] 제목\r\n\r\n첫 문단.\r\n\r\n둘째 문단.\r\n")
      assert_equal 2, body.body_paragraphs.size
      assert_equal 2, Design::SampleContent.for(doc_type: "chapter", locale: "ko").body_paragraphs.size
    end
  end

  test "save rejects a heading type without a valid heading block" do
    with_host_dir do
      c = Design::SampleContent.for(doc_type: "title_page", locale: "ko")
      err = assert_raises(Design::SampleContent::InvalidContent) { c.save("just text") }
      assert_equal :heading, err.reason
      err = assert_raises(Design::SampleContent::InvalidContent) { c.save("```heading\n---\ntitle: [unclosed\n---\n```") }
      assert_equal :yaml, err.reason
    end
  end

  test "save rejects heading YAML that is not a mapping" do
    with_host_dir do
      c = Design::SampleContent.for(doc_type: "title_page", locale: "ko")
      err = assert_raises(Design::SampleContent::InvalidContent) { c.save("```heading\n---\njust a string\n---\n```") }
      assert_equal :heading, err.reason
      err = assert_raises(Design::SampleContent::InvalidContent) { c.save("```heading\n---\n- a\n---\n```") }
      assert_equal :heading, err.reason
    end
  end

  test "save rejects a heading fence on a body type" do
    with_host_dir do
      c = Design::SampleContent.for(doc_type: "chapter", locale: "ko")
      err = assert_raises(Design::SampleContent::InvalidContent) { c.save("```heading\n---\ntitle: x\n---\n```") }
      assert_equal :heading_not_allowed, err.reason
    end
  end

  test "save rejects malformed toc rows and empty bodies" do
    with_host_dir do
      toc = Design::SampleContent.for(doc_type: "toc", locale: "ko")
      err = assert_raises(Design::SampleContent::InvalidContent) { toc.save("# [toc] 차례\n\n## not a row\n") }
      assert_equal :toc, err.reason
      toc.save("# [toc] 차례\n\n## 1:제1부:3\n## 2:제1장:5\n") # valid
      body = Design::SampleContent.for(doc_type: "chapter", locale: "ko")
      err = assert_raises(Design::SampleContent::InvalidContent) { body.save("   \n") }
      assert_equal :blank, err.reason
    end
  end

  test "save writes under the requested locale even when reads fall back to ko" do
    with_host_dir do |dir|
      c = Design::SampleContent.for(doc_type: "chapter", locale: "ja")
      assert c.exists? # ja has no bundled file → read falls back to ko
      c.save("# [chapter] 日本語\n\n本文です。\n")
      assert dir.join("ja/chapter.md").exist?
      refute dir.join("ko").exist?
      assert Design::SampleContent.for(doc_type: "chapter", locale: "ja").host_file?
    end
  end

  test "restore_default! removes the host file so the gem file is used again" do
    with_host_dir do |dir|
      c = Design::SampleContent.for(doc_type: "chapter", locale: "ko")
      c.save("# [chapter] x\n\ny\n")
      assert dir.join("ko/chapter.md").exist?
      c.restore_default!
      refute dir.join("ko/chapter.md").exist?
      refute Design::SampleContent.for(doc_type: "chapter", locale: "ko").host_file?
    end
  end

  test "restore_default! is a no-op when there is no host file" do
    with_host_dir do |dir|
      c = Design::SampleContent.for(doc_type: "chapter", locale: "ko")
      before = c.fingerprint
      c.restore_default!
      refute dir.join("ko").exist?
      assert c.exists?
      assert_equal before, c.fingerprint
    end
  end

  test "fingerprint is none when no file exists for the doc_type" do
    with_host_dir do
      assert_equal "none", Design::SampleContent.for(doc_type: "nonexistent_type", locale: "ko").fingerprint
    end
  end

  test "rejects doc_type or locale that could escape the content dir" do
    assert_raises(ArgumentError) { Design::SampleContent.for(doc_type: "../x", locale: "ko") }
    assert_raises(ArgumentError) { Design::SampleContent.for(doc_type: "chapter", locale: "../x") }
  end

  test "heading types match the bundled ko files that open with a heading fence" do
    fenced = Dir[Design::SampleContent::GEM_CONTENT_DIR.join("ko/*.md")]
      .select { |f| File.read(f).start_with?("```heading") }
      .map { |f| File.basename(f, ".md") }
      .sort
    assert_equal fenced, Design::SampleContent::HEADING_TYPES.sort
  end
end
