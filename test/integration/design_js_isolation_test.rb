require "test_helper"

class DesignJsIsolationTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david   # admin (can_design?)
    @theme = Design::Theme.create!(name: "JS #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  test "design layout loads the engine JS module" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_includes response.body, %(import "design")   # javascript_import_module_tag "design"
  end

  test "host pages do NOT load the engine JS module" do
    get root_path   # books#index, a host page
    assert_response :success
    assert_not_includes response.body, %(import "design")
  end

  # Activation proof (markup path): the doc-design edit form wires the
  # NAMESPACED engine controller `design--live-preview`, not the bare host
  # `live-preview` controller (cover_panels). This proves the view targets
  # the engine controller's identifier and is not silently host-masked.
  test "doc-design edit form wires the namespaced engine controller" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "form[data-controller~=?]", "design--live-preview"
    # and NOT the bare host identifier
    assert_select "form[data-controller~='live-preview']", false
  end
end
