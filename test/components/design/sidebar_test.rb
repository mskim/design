require "test_helper"

# Renders Design::Views::Sidebar directly (no controller). Route helpers are
# stubbed on the component the same way shell_test.rb stubs them on Shell.
class Design::SidebarTest < ActiveSupport::TestCase
  class FakeHelpers
    def theme_path(theme, **q) = "/themes/#{theme.id}" + (q.empty? ? "" : "?paper_size_id=#{q[:paper_size_id]}")
    def new_theme_paper_size_path(theme) = "/themes/#{theme.id}/paper_sizes/new"
    def edit_theme_paper_size_path(theme, ps) = "/themes/#{theme.id}/paper_sizes/#{ps.id}/edit"
    def generate_sizes_theme_path(theme) = "/themes/#{theme.id}/generate_sizes"
    def edit_theme_paper_size_document_design_path(theme, ps, dd) = "/themes/#{theme.id}/paper_sizes/#{ps.id}/document_designs/#{dd.id}/edit"
    def edit_theme_table_style_path(theme, ts) = "/themes/#{theme.id}/table_styles/#{ts.id}/edit"
    def form_authenticity_token = "tok"
  end

  setup do
    @theme = Design::Theme.create!(name: "Sb #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps    = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @other = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
  end

  def render_sidebar(**opts)
    component = Design::Views::Sidebar.new(theme: @theme, paper_size: @ps, **opts)
    component.define_singleton_method(:helpers) { FakeHelpers.new }
    Nokogiri::HTML.fragment(component.call)
  end

  test "renders one option per theme with the current theme selected" do
    doc = render_sidebar
    select = doc.at_css("select[data-sidebar='theme']")
    assert select, "theme select missing"
    assert_equal Design::Theme.count, select.css("option").size
    selected = select.at_css("option[selected]")
    assert_equal @theme.name, selected.text
    assert_equal "/themes/#{@theme.id}", selected["data-url"]
  end

  test "renders one option per paper size with the current size selected" do
    doc = render_sidebar
    select = doc.at_css("select[data-sidebar='size']")
    assert_equal 2, select.css("option").size
    assert_equal @ps.display_name, select.at_css("option[selected]").text
  end

  test "size options default to the theme overview for that size" do
    doc = render_sidebar
    option = doc.at_css("select[data-sidebar='size'] option:not([selected])")
    assert_equal "/themes/#{@theme.id}?paper_size_id=#{@other.id}", option["data-url"]
  end

  test "size options use the size_url lambda when given" do
    doc = render_sidebar(size_url: ->(ps) { "/custom/#{ps.id}" })
    urls = doc.css("select[data-sidebar='size'] option").map { |o| o["data-url"] }
    assert_equal [ "/custom/#{@ps.id}", "/custom/#{@other.id}" ], urls
  end

  test "both selects are wired to the navigate-select controller" do
    doc = render_sidebar
    assert_equal 2, doc.css("select[data-controller='design--navigate-select'][data-action='change->design--navigate-select#change']").size
  end

  test "renders without a paper size" do
    component = Design::Views::Sidebar.new(theme: @theme, paper_size: nil)
    component.define_singleton_method(:helpers) { FakeHelpers.new }
    doc = Nokogiri::HTML.fragment(component.call)
    assert doc.at_css("select[data-sidebar='theme']")
    assert_nil doc.at_css("select[data-sidebar='size'] option[selected]")
  end
end
