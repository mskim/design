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

  test "save rejects a heading type without a valid heading block" do
    with_host_dir do
      c = Design::SampleContent.for(doc_type: "title_page", locale: "ko")
      assert_raises(Design::SampleContent::InvalidContent) { c.save("just text") }
      assert_raises(Design::SampleContent::InvalidContent) { c.save("```heading\n---\ntitle: [unclosed\n---\n```") }
    end
  end

  test "save rejects malformed toc rows and empty bodies" do
    with_host_dir do
      toc = Design::SampleContent.for(doc_type: "toc", locale: "ko")
      assert_raises(Design::SampleContent::InvalidContent) { toc.save("# [toc] 차례\n\n## not a row\n") }
      toc.save("# [toc] 차례\n\n## 1:제1부:3\n## 2:제1장:5\n") # valid
      body = Design::SampleContent.for(doc_type: "chapter", locale: "ko")
      assert_raises(Design::SampleContent::InvalidContent) { body.save("   \n") }
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

  test "heading types are exactly the four heading-fenced files" do
    assert_equal %w[document_cover inside_cover part_cover title_page], Design::SampleContent::HEADING_TYPES.sort
  end
end
