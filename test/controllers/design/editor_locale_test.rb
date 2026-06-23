require "test_helper"

class Design::EditorLocaleTest < ActionDispatch::IntegrationTest
  test "edit page renders Korean editor chrome under :ko" do
    sign_in :david
    th = Design::Theme.create!(name: "E #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    ps = th.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")

    # The controller's around_action :switch_design_locale wraps every action in
    # its own I18n.with_locale(Design.config.locale_for || default), which would
    # override an outer I18n.with_locale(:ko). Force the design locale to :ko.
    Design.config.locale_for = -> { :ko }

    get design.edit_theme_paper_size_document_design_path(th, ps, dd)

    assert_response :success
    assert_includes response.body, "미리보기"          # Preview
    assert_includes response.body, "기본 텍스트 스타일"  # Base Text Styles
    refute_includes response.body, ">Preview<"
  end
end
