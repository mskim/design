# engines/design/test/services/design/theme_clone_service_test.rb
require "test_helper"

class Design::ThemeCloneServiceTest < ActiveSupport::TestCase
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
end
