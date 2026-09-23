require "test_helper"

# D4: the Object section validates only in the :object_section context and only
# the fields named by `object_field`. Always-on rules stay loose, so imports,
# Page-section saves and the tabs form can't break on old data.
class Design::ObjectSectionValidationTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "OSV #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225) # portrait: 6 x 12
    @copyright = @ps.document_designs.create!(doc_type: "copyright")
    @wing = @ps.document_designs.create!(doc_type: "front_wing")
  end

  def err(key, **opts) = I18n.t("design.object_section.errors.#{key}", **opts)

  def set(dd, values)
    dd.assign_attributes(values)
    dd.object_field = values.keys.map(&:to_s)
    dd.valid?(:object_section)
  end

  test "which fields each doc type owns, and the sets that must be written together" do
    assert_equal Design::DocumentDesign::OBJECT_TEXT_BOX_FIELDS, @copyright.object_fields
    assert_equal Design::DocumentDesign::OBJECT_PHOTO_FIELDS, @wing.object_fields
    assert_empty @ps.document_designs.create!(doc_type: "chapter").object_fields
    # One set each: the two cell sizes. The anchors save alone (decision 3).
    assert_equal [ %w[text_box_grid_width text_box_grid_height] ], @copyright.object_joint_sets
    assert_equal [ %w[photo_grid_width photo_grid_height] ], @wing.object_joint_sets
    assert_empty @ps.document_designs.create!(doc_type: "poem").object_joint_sets
  end

  test "anchor: a whole number 1-9" do
    { "0" => :out_of_range, "10" => :out_of_range, "99" => :out_of_range, "2.5" => :not_an_integer,
      "abc" => :not_an_integer, "" => :required }.each do |v, key|
      refute set(@copyright, text_box_anchor_position: v), v.inspect
      expected = key == :out_of_range ? err(key, min: 1, max: 9) : err(key)
      assert_equal [ expected ], @copyright.errors[:text_box_anchor_position], v.inspect
      @copyright.reload
    end
    assert set(@copyright, text_box_anchor_position: "5")
  end

  test "cell sizes are bounded by the page's own grid (portrait 6 x 12)" do
    assert_equal({ columns: 6, rows: 12 }, @copyright.object_grid)
    refute set(@copyright, text_box_grid_width: "7")
    assert_equal [ err(:out_of_range, min: 1, max: 6) ], @copyright.errors[:text_box_grid_width]
    @copyright.reload
    assert set(@copyright, text_box_grid_width: "6")
    @copyright.reload
    refute set(@copyright, text_box_grid_height: "13")
    assert_equal [ err(:out_of_range, min: 1, max: 12) ], @copyright.errors[:text_box_grid_height]
    @copyright.reload
    assert set(@copyright, text_box_grid_height: "12")
  end

  # The always-on rules stand down in this context, so the section's message —
  # the one that names the page's own grid — is the only one on the field.
  test "a value that breaks the loose rule too reports the section's message alone" do
    refute set(@copyright, text_box_grid_width: "40")
    assert_equal [ err(:out_of_range, min: 1, max: 6) ], @copyright.errors[:text_box_grid_width]
    @copyright.reload
    refute set(@wing, photo_grid_height: "40")
    assert_equal [ err(:out_of_range, min: 1, max: 12) ], @wing.errors[:photo_grid_height]
    @wing.reload
    refute set(@wing, photo_anchor: "40")
    assert_equal [ err(:out_of_range, min: 1, max: 9) ], @wing.errors[:photo_anchor]
  end

  test "a landscape page turns the grid around" do
    ps = @theme.paper_sizes.create!(size_name: "가로", width_mm: 297, height_mm: 210)
    dd = ps.document_designs.create!(doc_type: "copyright")
    assert_equal({ columns: 12, rows: 6 }, dd.object_grid)
    assert set(dd, text_box_grid_width: "12")
    dd.reload
    refute set(dd, text_box_grid_height: "7")
    assert_equal [ err(:out_of_range, min: 1, max: 6) ], dd.errors[:text_box_grid_height]
  end

  test "the joint set (both cell sizes) is validated as a whole, each against the grid" do
    refute set(@copyright, text_box_grid_width: "9", text_box_grid_height: "20")
    assert_equal [ err(:out_of_range, min: 1, max: 6) ], @copyright.errors[:text_box_grid_width]
    assert_equal [ err(:out_of_range, min: 1, max: 12) ], @copyright.errors[:text_box_grid_height]
    @copyright.reload
    assert set(@copyright, text_box_grid_width: "6", text_box_grid_height: "12")
    @copyright.reload
    # The anchor is written on its own: the engine defaults each field
    # separately, so an anchor with unset sizes renders fine (decision 3).
    assert set(@copyright, text_box_anchor_position: "9")
    assert_nil @copyright.text_box_grid_width
  end

  test "photo cells keep the flap's fixed 6 x 12, whatever the page's orientation" do
    assert_equal({ columns: 6, rows: 12 }, Design::DocumentDesign::PHOTO_GRID)
    refute set(@wing, photo_grid_width: "7")
    assert_equal [ err(:out_of_range, min: 1, max: 6) ], @wing.errors[:photo_grid_width]
    @wing.reload
    assert set(@wing, photo_grid_width: "6", photo_grid_height: "12")
    landscape = @theme.paper_sizes.create!(size_name: "가로2", width_mm: 297, height_mm: 210)
    wing = landscape.document_designs.create!(doc_type: "front_wing")
    refute set(wing, photo_grid_width: "7"), "the flap's grid never turns with the page"
    assert_equal [ err(:out_of_range, min: 1, max: 6) ], wing.errors[:photo_grid_width]
  end

  test "photo fit, border width and colour" do
    refute set(@wing, photo_fit: "stretch")
    assert_equal [ err(:bad_fit) ], @wing.errors[:photo_fit]
    @wing.reload
    assert set(@wing, photo_fit: "contain")
    @wing.reload
    refute set(@wing, photo_border_width: "-0.5")
    assert_equal [ err(:negative) ], @wing.errors[:photo_border_width]
    @wing.reload
    refute set(@wing, photo_border_width: "1e1")
    assert_equal [ err(:not_a_number) ], @wing.errors[:photo_border_width]
    @wing.reload
    assert set(@wing, photo_border_width: "0.75")
    @wing.reload
    # The renderers drop colour names (they need hex or CMYK), so the section does too.
    [ "black", "rgb(0,0,0)", "#12345" ].each do |bad|
      refute set(@wing, photo_border_color: bad), bad
      assert_equal [ err(:bad_color) ], @wing.errors[:photo_border_color], bad
      @wing.reload
    end
    [ "#1f2937", "CMYK=0,0,0,100" ].each { |good| assert set(@wing, photo_border_color: good), good; @wing.reload }
  end

  # In-range values: this test is about the section skipping a field it doesn't
  # own, not about the loose rules (which stand down in this context anyway).
  test "a field the doc type doesn't own is never checked here" do
    assert set(@copyright, photo_grid_width: "5"), "copyright has no photo inspector"
    @copyright.reload
    assert set(@wing, text_box_grid_width: "3"), "the front wing has no text box inspector"
    @wing.reload
    # …and the doc type that owns it does check it.
    refute set(@wing, photo_grid_width: "7")
    @wing.reload
    refute set(@copyright, text_box_grid_width: "7")
  end

  test "nothing is checked outside the :object_section context, or without object_field" do
    @copyright.text_box_grid_width = 99
    @copyright.object_field = %w[text_box_grid_width]
    refute @copyright.valid?, "…but the loose always-on rule still catches 99"
    @copyright.text_box_grid_width = 11
    assert @copyright.valid?, "11 cells is loose-legal: an import or a Page-section save must not break"
    @copyright.object_field = nil
    assert @copyright.valid?(:object_section)
  end

  test "the always-on rules are loose: 1-9 and 1-12, nil allowed — outside the section's context" do
    dd = @copyright
    { text_box_anchor_position: [ 1, 9 ], text_box_grid_width: [ 1, 12 ], text_box_grid_height: [ 1, 12 ] }
      .each do |field, (min, max)|
      dd.assign_attributes(field => nil)
      assert dd.valid?, "#{field} nil"
      [ min, max ].each { |v| dd[field] = v; assert dd.valid?, "#{field} #{v}" }
      [ min - 1, max + 1 ].each { |v| dd[field] = v; refute dd.valid?, "#{field} #{v}" }
      dd[field] = nil
    end
  end

  test "anchor_cell places and clamps exactly like DocLayout::Grid and cell_grid.js" do
    grid = { columns: 6, rows: 12 }
    cell = ->(a, w, h) { Design::DocumentDesign.anchor_cell(grid, a, w, h) }
    assert_equal({ x: 0.0, y: 0.0, w: 2.0, h: 3.0 }, cell.(1, 2, 3))
    assert_equal({ x: 2.0, y: 0.0, w: 2.0, h: 3.0 }, cell.(2, 2, 3))
    assert_equal({ x: 4.0, y: 0.0, w: 2.0, h: 3.0 }, cell.(3, 2, 3))
    assert_equal({ x: 0.0, y: 4.5, w: 2.0, h: 3.0 }, cell.(4, 2, 3))
    assert_equal({ x: 2.0, y: 4.5, w: 2.0, h: 3.0 }, cell.(5, 2, 3))
    assert_equal({ x: 4.0, y: 9.0, w: 2.0, h: 3.0 }, cell.(9, 2, 3))
    assert_equal({ x: 1.5, y: 0.0, w: 3.0, h: 1.0 }, cell.(2, 3, 1), "a centred odd span sits on a half cell")
    assert_equal({ x: 0.0, y: 0.0, w: 6.0, h: 12.0 }, cell.(5, 40, 40), "clamped to the grid")
    assert_equal({ x: 0.0, y: 11.5, w: 0.5, h: 0.5 }, cell.(7, 0, -3), "never smaller than half a cell")
    assert_equal cell.(1, 2, 3), cell.(0, 2, 3), "an out-of-range anchor clamps to 1"
    assert_equal cell.(9, 2, 3), cell.(99, 2, 3)
  end

  test "the effective box and the photo cell come from the columns, then the defaults" do
    assert_equal({ x: 0.0, y: 6.0, w: 4.0, h: 6.0 }, @copyright.text_box_cell, "unset: anchor 7, 4 x 6")
    @copyright.update!(text_box_anchor_position: 3, text_box_grid_width: 2)
    assert_equal({ x: 4.0, y: 0.0, w: 2.0, h: 6.0 }, @copyright.text_box_cell)
    assert_equal({ x: 0.0, y: 0.0, w: 3.0, h: 2.0 }, @wing.photo_cell, "column defaults, always at the sketch's top-left")
  end
end
