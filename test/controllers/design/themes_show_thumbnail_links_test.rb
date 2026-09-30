require "test_helper"

# A page thumbnail on the theme page opens that page's editor (the editor already
# previews the page, so there is no full-size preview overlay and no separate 편집 link).
class Design::ThemesShowThumbnailLinksTest < ActionDispatch::IntegrationTest
  setup { sign_in :david }

  test "an editable theme's thumbnails link to their editor, breaking out of the frame" do
    t = Design::Theme.create!(name: "Thumb #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    ps = t.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    chapter = ps.document_designs.create!(doc_type: "chapter")
    toc = ps.document_designs.create!(doc_type: "toc")

    stub_preview_service(success: false) { get design.theme_path(t) }

    assert_response :success
    [ chapter, toc ].each do |dd|
      path = design.edit_theme_paper_size_document_design_path(t, ps, dd)
      assert_select "a.doc-card__open[href=?][data-turbo-frame=_top][aria-label=?]",
        path, I18n.t("design.doc_types.#{dd.doc_type}")
      # the thumbnail is the only way in: no second (편집) link to the same editor
      assert_select "[data-doc-grid] a[href=?]", path, count: 1
    end
    assert_select ".doc-card button", count: 0
    assert_no_gallery
  end

  test "a read-only theme's thumbnails are plain, with no link or button" do
    Design.config.authoring = false
    t = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    ps = t.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")

    stub_preview_service(success: false) { get design.theme_path(t) }

    assert_response :success
    assert_select "div.doc-card__open", count: 1
    assert_select ".doc-card a", count: 0
    assert_select ".doc-card button", count: 0
    assert_select "a[href=?]", design.edit_theme_paper_size_document_design_path(t, ps, dd), count: 0
    assert_no_gallery
  end

  test "wing and seneca thumbnail links keep their narrower aspect ratio" do
    t = Design::Theme.create!(name: "Wing #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    ps = t.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    wing = ps.document_designs.create!(doc_type: "front_wing")
    seneca = ps.document_designs.create!(doc_type: "seneca")

    stub_preview_service(success: false) { get design.theme_path(t) }

    assert_response :success
    assert_select "a.doc-card__open[href=?][style*='aspect-ratio: 100 / 225']",
      design.edit_theme_paper_size_document_design_path(t, ps, wing)
    assert_select "a.doc-card__open[href=?][style*='aspect-ratio: 10 / 225']",
      design.edit_theme_paper_size_document_design_path(t, ps, seneca)
  end

  test "the preview gallery controller is gone" do
    refute File.exist?(Design::Engine.root.join("app/javascript/design-controllers/design/preview_gallery_controller.js"))
  end

  private

  def assert_no_gallery
    assert_not_includes response.body, "preview-gallery"
    assert_select "[data-index]", count: 0
  end

  def stub_preview_service(success:)
    fake = Object.new
    fake.define_singleton_method(:generate) { { success: success } }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original)
  end
end
