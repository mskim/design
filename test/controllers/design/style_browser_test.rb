require "test_helper"

class Design::StyleBrowserTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Br #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "renders the browser with four cascading auto-submit filters" do
    get design.style_browser_path
    assert_response :success
    assert_select "body.design-studio"
    assert_select "form[data-controller~='design--auto-submit']"
    assert_select "select[name=?]", "theme"
    assert_select "select[name=?]", "size"
    assert_select "select[name=?]", "doc_type"
    assert_select "select[name=?]", "style_name"
    assert_select "select[data-action~='change->design--auto-submit#submit']", minimum: 4
  end
end
