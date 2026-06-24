require "test_helper"

class Design::DesignPreviewImgTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "P #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  class Probe < Design::Views::Base
    def initialize(theme:, ps:, dd:) = (@theme = theme; @ps = ps; @dd = dd)
    def view_template
      design_preview_img(@theme, @ps, @dd, img_class: "thumb") { plain "NOPREVIEW" }
    end
  end

  def render
    c = Probe.new(theme: @theme, ps: @ps, dd: @dd)
    c.define_singleton_method(:helpers) do
      o = Object.new
      def o.preview_jpg_theme_paper_size_document_design_path(*, **) = "/preview.jpg"
      o
    end
    c.call
  end

  # factory-swap stub (the repo pattern — see document_designs_preview_test.rb)
  def stub_preview_service(success:)
    fake = Object.new
    fake.define_singleton_method(:generate) { { success: success } }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original)
  end

  test "renders the img when generate succeeds" do
    stub_preview_service(success: true) do
      html = render
      assert_includes html, %(src="/preview.jpg")
      assert_includes html, %(class="thumb")
      refute_includes html, "NOPREVIEW"
    end
  end

  test "renders the fallback when generate fails" do
    stub_preview_service(success: false) do
      html = render
      assert_includes html, "NOPREVIEW"
      refute_includes html, "<img"
    end
  end
end
