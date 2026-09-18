require "test_helper"
require "tmpdir"

class Design::SampleContentsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @dir = Dir.mktmpdir
    Design.config.sample_content_dir = @dir
    @theme = Design::Theme.create!(name: "Sc #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "edit shows the current (gem default) text in a textarea inside the studio shell" do
    get design.edit_theme_sample_content_path(@theme, "chapter", return_to: @dd.id)
    assert_response :success
    assert_select "aside select[data-sidebar='size']"
    assert_select "textarea[name=content]" do |ta|
      assert_includes ta.first.text, "본문"
    end
    assert_select "form[action=?]", design.restore_theme_sample_content_path(@theme, "chapter"), false, "no restore form while the gem default is in use"
  end

  test "update writes the host file and returns to the design editor" do
    patch design.theme_sample_content_path(@theme, "chapter"), params: { content: "# [chapter] 편집\n\n새 본문.\n", return_to: @dd.id }
    assert_redirected_to design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_equal "# [chapter] 편집\n\n새 본문.\n", File.read(File.join(@dir, "ko", "chapter.md"))
  end

  test "update without return_to goes to the theme overview" do
    patch design.theme_sample_content_path(@theme, "chapter"), params: { content: "# [chapter] x\n\ny\n" }
    assert_redirected_to design.theme_path(@theme)
  end

  test "invalid content re-renders 422 with the error and writes nothing" do
    patch design.theme_sample_content_path(@theme, "title_page"), params: { content: "not a heading block" }
    assert_response :unprocessable_entity
    assert_select "textarea[name=content]", text: /not a heading block/
    # The dummy app has no locale_for proc, so the request renders in I18n.default_locale (:en);
    # editor_locale_test.rb has to force locale_for to get Korean chrome.
    assert_includes response.body, I18n.t("design.sample_contents.errors.heading", locale: :en)
    refute File.exist?(File.join(@dir, "ko", "title_page.md"))
  end

  test "restore form appears once a host file exists, and restore deletes it" do
    FileUtils.mkdir_p(File.join(@dir, "ko"))
    File.write(File.join(@dir, "ko", "chapter.md"), "# [chapter] x\n\ny\n")
    get design.edit_theme_sample_content_path(@theme, "chapter", return_to: @dd.id)
    assert_select "form[action=?]", design.restore_theme_sample_content_path(@theme, "chapter")
    post design.restore_theme_sample_content_path(@theme, "chapter"), params: { return_to: @dd.id }
    assert_redirected_to design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    refute File.exist?(File.join(@dir, "ko", "chapter.md"))
  end

  test "unknown doc_type is not found" do
    get design.edit_theme_sample_content_path(@theme, "nope")
    assert_response :not_found
  end

  test "a non-designer is refused" do
    sign_in :kevin # role: member, can_design? false (same fixture the preview 403 test uses)
    get design.edit_theme_sample_content_path(@theme, "chapter")
    assert_response :forbidden
  end

  test "the design editor and the style edit page link to the sample editor" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_select "a[href=?]", design.edit_theme_sample_content_path(@theme, "chapter", return_to: @dd.id)
    style = @dd.paragraph_styles.create!(name: "body")
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: style.id)
    assert_select "a[href=?]", design.edit_theme_sample_content_path(@theme, "chapter", return_to: @dd.id)
  end
end
