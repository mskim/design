require "test_helper"

# Wing panels (back_wing / front_wing) must preview with their real engine
# renderers and panel-appropriate sample content — not the generic Chapter/lorem
# fallback. back_wing = promotional "other books"; front_wing = author profile.
class Design::PreviewWingTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "Wing #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "wing", width_mm: 100, height_mm: 225)
  end

  test "back_wing populates a heading + promoted_item blocks with generated cover images" do
    dd = @ps.document_designs.create!(doc_type: "back_wing")
    svc = Design::PreviewService.new(dd, paper_size: @ps)
    Dir.mktmpdir do |dir|
      svc.instance_variable_set(:@work_dir, dir)
      db_doc = DocProcessorRb::Database::DBDocument.new(path: File.join(dir, "t.db"), create_if_needed: true)
      db_doc.document_info # create the documents row the paragraphs FK references (populate_document does this in the real flow)
      svc.send(:populate_wing_blocks, db_doc)

      blocks = db_doc.blocks_for_component(component: "back_wing")
      assert_equal "heading", blocks.first.block_type
      assert blocks.first.content.present?, "heading should have text"

      items = blocks.select { |b| b.block_type == "promoted_item" }
      assert items.size >= 3, "expected several sample books, got #{items.size}"
      meta = items.first.parsed_metadata
      assert meta[:description].present?, "each book needs a description"
      assert meta[:image_path].present?, "each book needs a cover image path"
      assert File.exist?(meta[:image_path]), "cover image should be generated on disk"
      db_doc.close
    end
  end

  test "front_wing populates an author-name heading (with photo) + bio body" do
    dd = @ps.document_designs.create!(doc_type: "front_wing")
    svc = Design::PreviewService.new(dd, paper_size: @ps)
    Dir.mktmpdir do |dir|
      svc.instance_variable_set(:@work_dir, dir)
      db_doc = DocProcessorRb::Database::DBDocument.new(path: File.join(dir, "t.db"), create_if_needed: true)
      db_doc.document_info # create the documents row the paragraphs FK references (populate_document does this in the real flow)
      svc.send(:populate_wing_blocks, db_doc)

      blocks = db_doc.blocks_for_component(component: "front_wing")
      name = blocks.find { |b| b.block_type == "heading" }
      bio  = blocks.find { |b| b.block_type == "body" }
      assert name&.content.present?, "author name heading required"
      assert bio&.content.present?, "author bio body required"
      assert File.exist?(name.parsed_metadata[:image_path]), "author photo should be generated"
      db_doc.close
    end
  end

  test "wing sample data is localized (ko/en) by theme locale" do
    ko = Design::PreviewService.new(@ps.document_designs.create!(doc_type: "back_wing"), paper_size: @ps)
    assert_equal "다른 책들", ko.send(:back_wing_sample)[:heading]

    en_theme = Design::Theme.create!(name: "E #{SecureRandom.hex(3)}", locale: "en")
    en_ps = en_theme.paper_sizes.create!(size_name: "wing", width_mm: 100, height_mm: 225)
    en = Design::PreviewService.new(en_ps.document_designs.create!(doc_type: "back_wing"), paper_size: en_ps)
    assert_equal "Other Books", en.send(:back_wing_sample)[:heading]
  end

  test "back_wing preview renders end-to-end to a JPG" do
    dd = @ps.document_designs.create!(doc_type: "back_wing")
    svc = Design::PreviewService.new(dd, paper_size: @ps)
    result = svc.generate
    assert result[:success], "back_wing preview failed: #{result[:error]}"
    assert File.exist?(result[:jpg_path])
    assert File.size(result[:jpg_path]) > 1000
  ensure
    svc&.clear_cache
  end

  test "front_wing preview renders end-to-end to a JPG" do
    dd = @ps.document_designs.create!(doc_type: "front_wing")
    svc = Design::PreviewService.new(dd, paper_size: @ps)
    result = svc.generate
    assert result[:success], "front_wing preview failed: #{result[:error]}"
    assert File.exist?(result[:jpg_path])
    assert File.size(result[:jpg_path]) > 1000
  ensure
    svc&.clear_cache
  end
end
