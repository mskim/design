require "test_helper"

class Design::DocumentDesignsHeadingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "H #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
    @dd.heading_elements.create!(element_type: "title", style_name: "title", position: 0)
  end

  test "edit form renders the heading-elements + heading-bg sections, multipart" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "form[enctype='multipart/form-data']"
    assert_select "[data-controller~='design--heading-elements']"
    assert_select "[data-controller~='design--heading-bg']"
    assert_select "[data-design--heading-elements-target='template']"
    assert_includes response.body, "heading_elements_attributes][IDX]"
    assert_includes response.body, %(name="document_design[heading_elements_attributes][0][style_name]")
    assert_includes response.body, %(name="document_design[heading_bg_type]")
    assert_select "input[type=file][name='document_design[heading_bg_image]']"
  end

  test "update persists heading-element reorder/add/destroy + heading-bg + image" do
    file = Rack::Test::UploadedFile.new(StringIO.new("x"), "image/png", original_filename: "bg.png")
    existing = @dd.heading_elements.first
    patch design.theme_paper_size_document_design_path(@theme, @ps, @dd), params: { document_design: {
      heading_bg_type: "gradient", heading_bg_gradient_angle: 45,
      heading_bg_image: file,
      heading_elements_attributes: {
        "0" => { id: existing.id, element_type: "title", style_name: "title", position: "1" },
        "9999" => { element_type: "subtitle", style_name: "subtitle", position: "0" }
      }
    } }
    assert_response :redirect
    @dd.reload
    assert_equal "gradient", @dd.heading_bg_type
    assert_equal 45, @dd.heading_bg_gradient_angle
    assert @dd.heading_bg_image.attached?
    assert_equal 2, @dd.heading_elements.count
    assert_equal %w[subtitle title], @dd.heading_elements.order(:position).pluck(:element_type)
  end

  test "update can destroy a heading element" do
    existing = @dd.heading_elements.first
    patch design.theme_paper_size_document_design_path(@theme, @ps, @dd), params: { document_design: {
      heading_elements_attributes: { "0" => { id: existing.id, element_type: "title", style_name: "title", position: "0", _destroy: "1" } }
    } }
    assert_response :redirect
    assert_equal 0, @dd.reload.heading_elements.count
  end

  test "POST preview builds ephemeral heading elements from unsaved attrs without persisting" do
    @dd.heading_elements.create!(element_type: "author", style_name: "author", position: 1)
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    captured = nil
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |dd, **| captured = dd; fake }
    begin
      post design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd),
           params: { document_design: { heading_elements_attributes: {
             "0" => { element_type: "title", style_name: "title", position: "0" },
             "1" => { element_type: "author", style_name: "author", position: "1", _destroy: "1" } } } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    ensure
      Design::PreviewService.define_singleton_method(:new, original)
    end
    assert_response :success
    assert_equal 1, captured.heading_elements.size          # ephemeral; _destroy one excluded
    assert_equal "title", captured.heading_elements.first.element_type
    assert captured.heading_elements.none?(&:persisted?)
    assert_equal 2, @dd.reload.heading_elements.count        # real record UNCHANGED (data-loss fix)
  end
end
