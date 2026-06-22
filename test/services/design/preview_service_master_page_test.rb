require "test_helper"
require "tmpdir"

class Design::PreviewServiceMasterPageTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "PV #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225, body_line_count: 23)
    @dd = @ps.document_designs.create!(doc_type: "toc", toc_v_align: "center", body_line_count: 18)
  end

  test "master_page gets dd-level body_line_count and toc_v_align" do
    Dir.mktmpdir do |dir|
      svc = Design::PreviewService.new(@dd, paper_size: @ps)
      db_doc = svc.send(:create_db_document, File.join(dir, "t.db"))
      svc.send(:populate_document, db_doc)   # creates the document row (needed for FK)
      svc.send(:populate_master_page, db_doc)
      mp = db_doc.master_page
      assert_equal 18, mp.body_line_count
      assert_equal "center", mp.toc_v_align
      assert_in_delta @dd.body_line_height, mp.body_line_height, 0.001
      db_doc.close
    end
  end
end
