require "test_helper"

class Design::ThemesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david # admin (can_design?)
    @system_theme = Design::Theme.system_themes.first ||
      Design::Theme.create!(name: "Seoul", locale: "ko")
  end

  test "index renders a clone control for each theme card" do
    get "/design/themes"

    assert_response :success
    assert_select "form[action=?]", "/design/themes/#{@system_theme.id}/clone"
  end

  test "index renders a delete control for an editable (owned) theme" do
    theme = Design::Theme.create!(name: "Mine", locale: "ko", user: users(:david))

    get "/design/themes"

    assert_select %(form[action="/design/themes/#{theme.id}"] input[name="_method"][value="delete"])
  end

  test "index hides the from-scratch New theme button on a consumer host" do
    Design.config.authoring = false

    get "/design/themes"

    assert_select %(a[href="/design/themes/new"]), false
  end

  test "index shows the from-scratch New theme button on an authoring host" do
    Design.config.authoring = true

    get "/design/themes"

    assert_select %(a[href="/design/themes/new"])
  end

  test "index renders a rename control for an editable theme" do
    theme = Design::Theme.create!(name: "Mine", locale: "ko", user: users(:david))

    get "/design/themes"

    assert_select %(form[action="/design/themes/#{theme.id}"] input[name="theme[name]"])
  end

  test "index omits the delete control for a read-only system theme (consumer host)" do
    Design.config.authoring = false

    get "/design/themes"

    assert_select %(form[action="/design/themes/#{@system_theme.id}"] input[name="_method"][value="delete"]), false
  end

  test "index renders a delete control for a system theme on an authoring host" do
    Design.config.authoring = true

    get "/design/themes"

    assert_select %(form[action="/design/themes/#{@system_theme.id}"] input[name="_method"][value="delete"])
  end

  test "clone uses the submitted name for the new theme" do
    assert_difference -> { Design::Theme.where(user: users(:david)).count }, +1 do
      post "/design/themes/#{@system_theme.id}/clone", params: { name: "My Brochure Theme" }
    end

    assert_equal "My Brochure Theme", Design::Theme.where(user: users(:david)).order(:created_at).last.name
  end

  test "clone falls back to the auto name when none is submitted" do
    post "/design/themes/#{@system_theme.id}/clone"

    cloned = Design::Theme.where(user: users(:david)).order(:created_at).last
    assert_equal "#{@system_theme.name} (Custom)", cloned.name
  end

  test "update renames a theme owned by the current user" do
    theme = Design::Theme.create!(name: "Old Name", locale: "ko", user: users(:david))

    patch "/design/themes/#{theme.id}", params: { theme: { name: "New Name" } }

    assert_redirected_to "/design/themes"
    assert_equal "New Name", theme.reload.name
  end

  test "update is forbidden for a system theme (not owned by the user)" do
    patch "/design/themes/#{@system_theme.id}", params: { theme: { name: "Hijacked" } }

    assert_response :forbidden
    assert_not_equal "Hijacked", @system_theme.reload.name
  end

  test "update renames a custom theme created by another designer (shared house)" do
    other = User.create!(email_address: "other-#{SecureRandom.hex(3)}@example.com",
                         password: "password123", name: "Other")
    theme = Design::Theme.create!(name: "Theirs", locale: "ko", user: other)

    patch "/design/themes/#{theme.id}", params: { theme: { name: "House Rename" } }

    assert_redirected_to "/design/themes"
    assert_equal "House Rename", theme.reload.name
  end

  test "update with a blank name does not rename and reports an error" do
    theme = Design::Theme.create!(name: "Keep Me", locale: "ko", user: users(:david))

    patch "/design/themes/#{theme.id}", params: { theme: { name: "  " } }

    assert_equal "Keep Me", theme.reload.name
  end

  test "index renders a chapter preview image for a theme that has one" do
    theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")

    # The flat index now generates previews on render (design_preview_img),
    # so a theme with a chapter doc triggers a PreviewService shell-out — stub it.
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg" }
    stub_preview_service(fake) do
      get design.themes_path
    end

    assert_response :success
    assert_select "img[src=?]", design.preview_jpg_theme_paper_size_document_design_path(theme, ps, dd)
  end

  test "index omits the preview strip for a theme without a chapter doc" do
    theme = Design::Theme.create!(name: "Empty #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)

    # No chapter doc on the default size → the flat card renders no preview
    # strip at all (the old grid had a .preview-empty placeholder; the
    # redesigned card simply omits the image area).
    get design.themes_path

    assert_response :success
    assert_select ".theme-card img", count: 0
    assert_includes response.body, theme.name
  end

  # Minitest 6 dropped Object#stub; swap the class .new manually and restore.
  def stub_preview_service(fake)
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original)
  end

  test "show renders a preview image per doc-type of the selected size and no style list" do
    theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    chapter = ps.document_designs.create!(doc_type: "chapter")
    toc = ps.document_designs.create!(doc_type: "toc")

    get design.theme_path(theme)

    assert_response :success
    assert_select "img[src=?]", design.preview_jpg_theme_paper_size_document_design_path(theme, ps, chapter)
    assert_select "img[src=?]", design.preview_jpg_theme_paper_size_document_design_path(theme, ps, toc)
    assert_select "[data-doc-grid] img", count: 2
    assert_select "h2", text: I18n.t("design.themes.base_text_styles"), count: 0
  end

  test "show grid includes cover-panel doc types in the book-cover section" do
    theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    chapter = ps.document_designs.create!(doc_type: "chapter")
    seneca = ps.document_designs.create!(doc_type: "seneca")

    get design.theme_path(theme)

    assert_response :success
    assert_select "img[src=?]", design.preview_jpg_theme_paper_size_document_design_path(theme, ps, chapter)
    assert_select "img[src=?]", design.preview_jpg_theme_paper_size_document_design_path(theme, ps, seneca)
    assert_select "[data-doc-grid] img", count: 2
  end

  test "show size selector switches which size's docs render" do
    theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    a4 = theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    sk = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    a4_dd = a4.document_designs.create!(doc_type: "chapter")
    sk_dd = sk.document_designs.create!(doc_type: "chapter")

    get design.theme_path(theme)
    assert_select "img[src=?]", design.preview_jpg_theme_paper_size_document_design_path(theme, a4, a4_dd)

    get design.theme_path(theme, paper_size_id: sk.id)
    assert_select "img[src=?]", design.preview_jpg_theme_paper_size_document_design_path(theme, sk, sk_dd)
    assert_select "img[src=?]", design.preview_jpg_theme_paper_size_document_design_path(theme, a4, a4_dd), count: 0
  end

  test "generate_sizes is forbidden on a read-only system theme" do
    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko")
    post "/design/themes/#{system_theme.id}/generate_sizes"
    assert_response :forbidden
  end

  test "generate_sizes is allowed on an editable custom theme" do
    custom = Design::Theme.create!(name: "Cust #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    post "/design/themes/#{custom.id}/generate_sizes"
    assert_response :redirect
  end

  test "show offers per-document edit links for an editable (custom) theme only" do
    custom = Design::Theme.create!(name: "Mine #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    ps = custom.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")

    get design.theme_path(custom)
    assert_select "a[href=?]", design.edit_theme_paper_size_document_design_path(custom, ps, dd)

    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    sdd = sps.document_designs.create!(doc_type: "chapter")
    get design.theme_path(system_theme)
    assert_select "a[href=?]", design.edit_theme_paper_size_document_design_path(system_theme, sps, sdd), count: 0
  end
end
