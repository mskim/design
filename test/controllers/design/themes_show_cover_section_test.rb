require "test_helper"

class Design::ThemesShowCoverSectionTest < ActionDispatch::IntegrationTest
  setup { sign_in :david }   # the cover Edit link is gated on editability

  test "show renders a book-cover section with an Edit link to a cover doc-type" do
    t = Design::Theme.create!(name: "ShowCover #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    ps = t.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    %w[chapter front_page].each { |d| ps.document_designs.create!(doc_type: d) }
    front_page_dd = ps.document_designs.find_by!(doc_type: "front_page")
    stub_preview_service(success: false) do   # avoid shelling out; cards fall back to placeholder
      get design.theme_path(t)
    end
    assert_response :success
    assert_select "a[href=?]",
      design.edit_theme_paper_size_document_design_path(t, ps, front_page_dd)
    assert_includes response.body, I18n.t("design.themes.cover")
  end

  test "wing cards preview at 100mm and seneca at 80mm, not the page width" do
    t = Design::Theme.create!(name: "Wing #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    ps = t.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    %w[front_wing seneca].each { |d| ps.document_designs.create!(doc_type: d) }
    stub_preview_service(success: false) do
      get design.theme_path(t)
    end
    assert_response :success
    # every card sits in a page-shaped row (152x225) so all cover parts are the SAME height
    assert_select "[style*='aspect-ratio: 152 / 225']"
    # the preview inside is the panel's true width: wing 100mm, seneca (spine) 80mm
    assert_select "[style*='aspect-ratio: 100 / 225']"   # wing
    assert_select "[style*='aspect-ratio: 80 / 225']"    # seneca
  end

  # factory-swap stub — copy the helper from themes_show_grouped_test.rb
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
