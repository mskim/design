# engines/design/test/services/design/theme_clone_service_test.rb
require "test_helper"

class Design::ThemeCloneServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @user = User.create!(email_address: "u-#{SecureRandom.hex(3)}@example.com",
                         password: "password123", name: "U")
    @source = Design::Theme.create!(name: "Src #{SecureRandom.hex(3)}", locale: "ko",
                                    base_body_font: "smShinShinMyungjoP-30",
                                    base_body_font_size: 9.5,
                                    base_heading_font: "NotoSerifKR-Bold")
  end

  test "clones all 5 table_styles" do
    @source.table_styles.find_by(name: "zebra").update!(border_width: 99.0)

    cloned = Design::ThemeCloneService.new(@source, user: @user).clone

    assert_equal 5, cloned.table_styles.count
    assert_equal 99.0, cloned.table_styles.find_by(name: "zebra").border_width.to_f
  end

  # The returned theme reads its copied rows, not the seeded defaults the clone destroyed: an export
  # (ThemeDbExportService walks the loaded associations) once wrote a .db with no table styles.
  test "the returned theme's associations show what was copied" do
    cloned = Design::ThemeCloneService.new(@source, user: @user).clone

    assert_equal @source.table_styles.map(&:name).sort, cloned.table_styles.to_a.map(&:name).sort
    assert_equal @source.base_paragraph_styles.map(&:name).sort, cloned.base_paragraph_styles.to_a.map(&:name).sort
  end

  test "deep-copies paper sizes, document designs, and their styles" do
    # The original bug: clone only copied the first paper size + first document
    # design, then died on a ParagraphStyle name collision (a created document
    # design seeds its own default styles via an after_create callback, which the
    # clone then duplicated on top of). The fix clears seeded rows before copying.
    # NOTE: in the dummy app DefaultGenerator seeds nothing, so styles here are
    # added explicitly to verify the copy is exhaustive and correctly re-parented.
    ps = @source.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")
    dd.paragraph_styles.create!(name: "body", font: "smShinShinMyungjoP-30", font_size: 9.5)
    dd.heading_elements.create!(element_type: "title", style_name: "title", position: 0)

    cloned = Design::ThemeCloneService.new(@source, user: @user, name: "Deep #{SecureRandom.hex(3)}").clone

    assert_equal @source.paper_sizes.count, cloned.paper_sizes.count, "all paper sizes copied"
    assert_equal @source.document_designs.count, cloned.document_designs.count, "all document designs copied"
    cloned_dd = cloned.paper_sizes.first.document_designs.find_by(doc_type: "chapter")
    assert_not_nil cloned_dd
    assert cloned_dd.paragraph_styles.exists?(name: "body"), "dd paragraph styles copied"
    assert_equal dd.heading_elements.count, cloned_dd.heading_elements.count, "dd heading elements copied"
    # The copy must be re-parented onto the clone, not point back at the source.
    assert_not_equal dd.id, cloned_dd.id
  end

  test "a failed clone persists no partial theme (transactional)" do
    ps = @source.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.document_designs.create!(doc_type: "chapter")
    before_themes = Design::Theme.count
    before_dds = Design::DocumentDesign.count

    # Force a failure after most of the copy has happened; the transaction must
    # roll the whole thing back (no half-built theme like the original bug left).
    service = Design::ThemeCloneService.new(@source, user: @user, name: "WillFail")
    service.define_singleton_method(:clone_table_styles) { |_| raise "boom" }

    assert_raises(RuntimeError) { service.clone }

    assert_equal before_themes, Design::Theme.count, "no theme should persist"
    assert_equal before_dds, Design::DocumentDesign.count, "no document designs should persist"
    assert_nil Design::Theme.find_by(name: "WillFail")
  end

  test "clones table cell paragraph styles" do
    cloned = Design::ThemeCloneService.new(@source, user: @user).clone

    assert cloned.base_paragraph_styles.exists?(name: "table_heading_cell")
    assert cloned.base_paragraph_styles.exists?(name: "table_body_cell")
  end

  test "uses the provided name when one is given" do
    cloned = Design::ThemeCloneService.new(@source, user: @user, name: "My Custom Theme").clone

    assert_equal "My Custom Theme", cloned.name
  end

  test "falls back to the auto-generated name when the given name is blank" do
    cloned = Design::ThemeCloneService.new(@source, user: @user, name: "   ").clone

    assert_equal "#{@source.name} (Custom)", cloned.name
  end

  test "disambiguates a duplicate provided name" do
    Design::Theme.create!(name: "Dup", locale: "ko", user: @user)

    cloned = Design::ThemeCloneService.new(@source, user: @user, name: "Dup").clone

    assert_equal "Dup 2", cloned.name
  end

  # --- book designs: one paper size into a theme owned by a book -------------

  def build_two_sizes
    @shin = @source.paper_sizes.create!(size_name: "shinkook", local_name: "신국판", width_mm: 152, height_mm: 225)
    @a4 = @source.paper_sizes.create!(allow_another_size: true, size_name: "A4", local_name: "A4", width_mm: 210, height_mm: 297)
    [ @shin, @a4 ].each do |ps|
      ps.paragraph_styles.create!(name: "ps_body_#{ps.size_name}", font: "smShinShinMyungjoP-30", font_size: 9.5)
      %w[chapter toc].each do |doc_type|
        dd = ps.document_designs.create!(doc_type: doc_type)
        dd.paragraph_styles.create!(name: "body", font: "smShinShinMyungjoP-30", font_size: 9.5)
        dd.heading_elements.create!(element_type: "title", style_name: "title", position: 0)
      end
    end
    @source.update!(imported_at: Time.current)
  end

  def style_rows(styles)
    styles.order(:name).map { |st| st.attributes.except("id", "styleable_id", "created_at", "updated_at") }
  end

  def dd_rows(paper_size)
    paper_size.document_designs.order(:doc_type).map do |dd|
      [ dd.attributes.except("id", "paper_size_id", "created_at", "updated_at"),
        style_rows(dd.paragraph_styles),
        dd.heading_elements.order(:position).map { |he| he.attributes.except("id", "document_design_id", "created_at", "updated_at") } ]
    end
  end

  test "clones one paper size into a book design" do
    build_two_sizes

    service = Design::ThemeCloneService.new(@source, user: nil, book_id: 7, paper_size: "신국판")
    design = service.clone

    assert_equal 7, design.book_id
    assert_nil design.user_id
    assert_equal @source.id, design.source_theme_id
    assert_equal @source.name, design.name
    assert_nil design.imported_at
    assert design.book_design?
    assert_not service.fell_back?

    assert_equal [ "신국판" ], design.paper_sizes.map(&:local_name)
    copied = design.paper_sizes.first
    assert_equal style_rows(@shin.paragraph_styles), style_rows(copied.paragraph_styles)
    assert_equal dd_rows(@shin), dd_rows(copied)
    assert_equal style_rows(@source.base_paragraph_styles), style_rows(design.base_paragraph_styles)
    assert_equal @source.table_styles.order(:name).map { |t| t.attributes.except("id", "theme_id", "created_at", "updated_at") },
                 design.table_styles.order(:name).map { |t| t.attributes.except("id", "theme_id", "created_at", "updated_at") }

    names = design.base_paragraph_styles.pluck(:name)
    assert_equal names.uniq, names, "no seeded duplicates"
  end

  test "a missing paper size falls back to the source's first size" do
    build_two_sizes

    service = Design::ThemeCloneService.new(@source, book_id: 7, paper_size: "국배판")
    design = service.clone

    assert service.fell_back?
    assert_equal [ @source.default_paper_size.local_name ], design.paper_sizes.map(&:local_name)
    assert_equal "신국판", design.paper_sizes.first.local_name
  end

  test "without paper_size every size is copied into the book design" do
    build_two_sizes

    service = Design::ThemeCloneService.new(@source, book_id: 7)
    design = service.clone

    assert_not service.fell_back?
    assert_equal %w[신국판 A4].sort, design.paper_sizes.map(&:local_name).sort
  end

  test "a starter with no paper sizes copies into a design with none" do
    service = Design::ThemeCloneService.new(@source, book_id: 7, paper_size: "신국판")
    design = service.clone

    assert design.persisted?
    assert_empty design.paper_sizes
  end

  test "two books get designs with the starter's own name" do
    a = Design::ThemeCloneService.new(@source, book_id: 7).clone
    b = Design::ThemeCloneService.new(@source, book_id: 8).clone

    assert_equal [ @source.name, @source.name ], [ a.name, b.name ]
  end

  test "a user clone is unchanged: Custom name, every size, no book" do
    build_two_sizes

    cloned = Design::ThemeCloneService.new(@source, user: @user).clone

    assert_equal "#{@source.name} (Custom)", cloned.name
    assert_equal @user.id, cloned.user_id
    assert_nil cloned.book_id
    assert_nil cloned.source_theme_id
    assert_equal 2, cloned.paper_sizes.count
  end

  test "clone_paper_size_into copies one size into an existing theme" do
    build_two_sizes
    design = Design::ThemeCloneService.new(@source, book_id: 7, paper_size: "신국판").clone

    Design::ThemeCloneService.new(@source).clone_paper_size_into(design, @a4)

    added = design.paper_sizes.find_by(local_name: "A4")
    assert_not_nil added
    assert_equal style_rows(@a4.paragraph_styles), style_rows(added.paragraph_styles)
    assert_equal dd_rows(@a4), dd_rows(added)
  end

  test "copies a document design's start_on_right" do
    ps = @source.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.document_designs.create!(doc_type: "part_cover", start_on_right: true)

    cloned = Design::ThemeCloneService.new(@source, user: @user).clone

    assert cloned.paper_sizes.find_by!(size_name: "신국판").document_designs.find_by!(doc_type: "part_cover").start_on_right
  end

  test "copies a document design's chapter_number_format" do
    ps = @source.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.document_designs.create!(doc_type: "chapter", chapter_number_format: "Chapter {n}")

    cloned = Design::ThemeCloneService.new(@source, user: @user).clone

    assert_equal "Chapter {n}", cloned.paper_sizes.find_by!(size_name: "신국판").document_designs.find_by!(doc_type: "chapter").chapter_number_format
  end

  test "copies a document design's back flap layout" do
    ps = @source.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.document_designs.create!(doc_type: "back_wing", back_wing_image_width_percent: 25, back_wing_image_ratio: 1.6, back_wing_item_gap: 6)

    cloned = Design::ThemeCloneService.new(@source, user: @user).clone
    wing = cloned.paper_sizes.find_by!(size_name: "신국판").document_designs.find_by!(doc_type: "back_wing")

    assert_equal [ 25, 1.6, 6.0 ], [ wing.back_wing_image_width_percent, wing.back_wing_image_ratio.to_f, wing.back_wing_item_gap.to_f ]
  end

  # dup skips attachments. The copy shares the blob: ActiveStorage keeps a blob
  # while any attachment uses it, so destroying the source (a split) is safe.
  test "a document design's heading background image is copied" do
    ps = @source.paper_sizes.create!(size_name: "신국판", local_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")
    dd.heading_bg_image.attach(io: StringIO.new("img"), filename: "bg.png", content_type: "image/png")

    cloned = Design::ThemeCloneService.new(@source, user: @user, paper_size: ps).clone
    image = cloned.document_designs.find_by!(doc_type: "chapter").heading_bg_image

    assert image.attached?
    assert_equal dd.heading_bg_image.blob, image.blob
    perform_enqueued_jobs { ps.destroy! }
    assert ActiveStorage::Blob.exists?(image.blob.id), "the copy keeps its image"
  end

  test "paper_size: a size of another theme is refused" do
    other = Design::Theme.create!(name: "Other #{SecureRandom.hex(3)}", locale: "ko")
    ps = other.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)

    assert_raises(ArgumentError) { Design::ThemeCloneService.new(@source, user: @user, paper_size: ps).clone }
  end
end
