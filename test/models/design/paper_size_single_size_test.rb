require "test_helper"

# A design has one paper size; another size is another design (SizedCopyService).
class Design::PaperSizeSingleSizeTest < ActiveSupport::TestCase
  setup { @theme = Design::Theme.create!(name: "One #{SecureRandom.hex(3)}", locale: "ko") }

  test "a theme's first size is created" do
    ps = @theme.paper_sizes.create(size_name: "152mmx225mm", width_mm: 152, height_mm: 225)
    assert ps.persisted?
  end

  test "a second size on the same theme is refused" do
    @theme.paper_sizes.create!(size_name: "152mmx225mm", width_mm: 152, height_mm: 225)
    second = @theme.paper_sizes.create(size_name: "210mmx297mm", width_mm: 210, height_mm: 297)

    refute second.persisted?
    assert second.errors.added?(:theme, :one_size_only)
  end

  test "an existing multi-size theme's sizes still save" do
    first = @theme.paper_sizes.create!(size_name: "152mmx225mm", width_mm: 152, height_mm: 225)
    legacy = @theme.paper_sizes.create!(size_name: "210mmx297mm", width_mm: 210, height_mm: 297, allow_another_size: true)

    assert legacy.update(top_margin_mm: 20)
    assert first.update(top_margin_mm: 18)
  end

  test "STANDARD_SIZES lists the Korean book sizes, A4 and A5, each with an ASCII en_name" do
    sizes = Design::PaperSize::STANDARD_SIZES.index_by { |s| s[:local_name] }

    assert_equal %w[신국판 사륙판 국판 크라운판 사륙배판 A4 A5], sizes.keys
    assert_equal [ 128, 188 ], sizes["사륙판"].values_at(:width_mm, :height_mm)
    assert_equal "128mmx188mm", sizes["사륙판"][:size_name]
    assert_equal "128x188", sizes["사륙판"][:en_name]
    assert_equal [ 148, 210 ], sizes["A5"].values_at(:width_mm, :height_mm)
    assert(sizes.values.all? { |s| s[:en_name].ascii_only? })
  end
end
