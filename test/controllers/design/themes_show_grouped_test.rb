require "test_helper"

class Design::ThemesShowGroupedTest < ActionDispatch::IntegrationTest
  setup { sign_in :david }   # the "Edit Theme" button is gated on editability

  test "show groups interior doc designs into matter sections in order" do
    t = Design::Theme.create!(name: "ShowG #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    ps = t.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    %w[appendix chapter title_page].each { |d| ps.document_designs.create!(doc_type: d) }
    stub_preview_service(success: false) do   # avoid shelling out; cards fall back to placeholder
      get design.theme_path(t)
    end
    assert_response :success
    body = response.body
    assert_operator body.index(I18n.t("design.themes.frontmatter")), :<, body.index(I18n.t("design.themes.bodymatter"))
    assert_operator body.index(I18n.t("design.themes.bodymatter")), :<, body.index(I18n.t("design.themes.rearmatter"))
    assert_select "a[href=?]", design.edit_theme_path(t)   # native Edit Theme (owned + signed-in)
  end

  # factory-swap stub — copy the helper from document_designs_preview_test.rb
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
