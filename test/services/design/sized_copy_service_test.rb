require "test_helper"
require "sqlite3"

class Design::SizedCopyServiceTest < ActiveSupport::TestCase
  setup do
    @user = sign_in(:david)
    @source = Design::Theme.create!(name: "클래식 #{SecureRandom.hex(3)}", locale: "ko")
    @source.base_paragraph_styles.create!(name: "body", font: "BaseFont", font_size: 10)
    @source.base_paragraph_styles.create!(name: "title", font_size: 24)
    @source_ps = @source.paper_sizes.create!(size_name: "152mmx225mm", local_name: "신국판", width_mm: 152, height_mm: 225)
    @source_ch = @source_ps.document_designs.create!(doc_type: "chapter")
  end

  teardown { @copies&.each { |t| File.delete(t.db_path) if File.exist?(t.db_path) } }

  def copy!(source = @source, **size)
    size = standard("사륙판") if size.empty?
    Design::SizedCopyService.new(source, **size).call.tap { |t| (@copies ||= []) << t }
  end

  def standard(local_name) = Design::PaperSize::STANDARD_SIZES.find { |s| s[:local_name] == local_name }

  test "the copy is a new design with one size, rescaled to the target" do
    copy = copy!

    assert_not_equal @source.id, copy.id
    ps = copy.paper_sizes.sole
    assert_equal [ "128mmx188mm", "사륙판", 128, 188 ], [ ps.size_name, ps.local_name, ps.width_mm.to_i, ps.height_mm.to_i ]

    ratio_w = 128.0 / 152
    assert_in_delta (@source_ps.left_margin_mm * ratio_w).round(2), ps.left_margin_mm.to_f, 0.001
    title = ps.document_designs.find_by!(doc_type: "chapter").paragraph_styles.find_by!(name: "title")
    source_title = @source_ch.paragraph_styles.find_by!(name: "title")
    assert_in_delta (source_title.font_size * 188 / 225).round(2), title.font_size.to_f, 0.001
  end

  test "a Korean source names the copy with the size's Korean name" do
    assert_equal "#{@source.name} 사륙판", copy!.name
    assert_equal "ko", copy!.locale
  end

  test "an English source names the copy with the size's ASCII label" do
    en = Design::Theme.create!(name: "Classic #{SecureRandom.hex(3)}", locale: "en")
    en.paper_sizes.create!(size_name: "152mmx225mm", local_name: "신국판", width_mm: 152, height_mm: 225)
      .document_designs.create!(doc_type: "chapter")

    assert_equal "#{en.name} 128x188", copy!(en).name
    assert_equal "#{en.name} A5", copy!(en, **standard("A5")).name
  end

  test "a custom size is named <W>x<H>" do
    copy = copy!(width_mm: 150, height_mm: 220.5)

    assert_equal "#{@source.name} 150x220.5", copy.name
    ps = copy.paper_sizes.sole
    assert_equal [ "150mmx220.5mm", "150x220.5" ], [ ps.size_name, ps.local_name ]
  end

  test "a requested name wins" do
    assert_equal "작은 클래식", copy!(width_mm: 128, height_mm: 188, name: "작은 클래식").name
  end

  test "the source is untouched" do
    before = [ @source.paper_sizes.count, @source_ps.reload.attributes, @source_ch.paragraph_styles.map(&:attributes) ]
    copy!

    assert_equal before, [ @source.paper_sizes.count, @source_ps.reload.attributes, @source_ch.paragraph_styles.reload.map(&:attributes) ]
  end

  test "the copy's own .db is exported" do
    copy = copy!

    assert File.exist?(copy.db_path)
    db = SQLite3::Database.new(copy.db_path)
    assert_equal [ [ "128mmx188mm", 128.0 ] ], db.execute("SELECT size_name, width_mm FROM paper_sizes")
  ensure
    db&.close
  end

  test "a system source on a consumer host gives the current user's custom copy" do
    Design.config.authoring = false
    assert_equal @user, copy!.user
  end

  test "a system source on an authoring host gives a system copy" do
    Design.config.authoring = true
    assert copy!.system?
  end

  test "a custom source gives the current user's custom copy" do
    @source.update!(user: users(:kevin))
    Design.config.authoring = true
    assert_equal @user, copy!.user
  end

  def db_theme_names(path)
    db = SQLite3::Database.new(path)
    db.execute("SELECT name FROM themes").flatten
  ensure
    db&.close
  end

  test "a copy of an ASCII-named design keeps its .db off the source's" do
    Design.config.authoring = true # a system copy, next to its source
    classic = Design::Theme.create!(name: "Classic #{SecureRandom.hex(3)}", locale: "ko")
    classic.paper_sizes.create!(size_name: "152mmx225mm", local_name: "신국판", width_mm: 152, height_mm: 225)
           .document_designs.create!(doc_type: "chapter")
    Design::ThemeDbExportService.new(classic).export!

    copy = copy!(classic)

    assert_equal "#{classic.name} 사륙판", copy.name
    assert_not_equal classic.db_path, copy.db_path
    assert_equal [ classic.name ], db_theme_names(classic.db_path)
  ensure
    File.delete(classic.db_path) if classic && File.exist?(classic.db_path)
  end

  test "two size copies of one custom design get their own .db" do
    @source.update!(name: "Mine #{SecureRandom.hex(3)}", user: @user)

    a = copy!
    b = copy!(**standard("국판"))

    assert_not_equal a.db_path, b.db_path
    assert_equal [ a.name ], db_theme_names(a.db_path)
    assert_equal [ b.name ], db_theme_names(b.db_path)
  end

  test "with no signed-in user (console, rake) a custom source's copy keeps its owner" do
    @source.update!(user: users(:kevin))
    sign_out

    assert_equal users(:kevin), copy!.user
  end

  test "the source's own size is the one copied, whatever its local name" do
    @source_ps.update!(local_name: nil)
    copy = copy!

    assert_equal [ 128, 188 ], copy.paper_sizes.sole.then { |ps| [ ps.width_mm.to_i, ps.height_mm.to_i ] }
  end

  # The copy is committed before its .db is written: an export failure leaves
  # the copy (a resubmit would make "<name> 2") and is reported, not raised.
  test "an export failure keeps the copy and is reported" do
    service = Design::SizedCopyService.new(@source, **standard("사륙판"))
    failing_export do
      copy = service.call
      assert copy.persisted?
      assert_equal 1, copy.paper_sizes.count
      assert_match(/disk full/, service.export_error.message)
    end
  end

  def failing_export
    failing = Object.new
    failing.define_singleton_method(:export!) { raise "disk full" }
    Design::ThemeDbExportService.define_singleton_method(:new) { |*| failing }
    yield
  ensure
    Design::ThemeDbExportService.singleton_class.send(:remove_method, :new)
  end
end
