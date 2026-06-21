require "test_helper"

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
end
