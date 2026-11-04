require "test_helper"
require "rake"
require "sqlite3"

# Collapsing a legacy multi-size theme to one size (a design has one size).
class Design::SingleSizeTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "클래식 #{SecureRandom.hex(3)}", locale: "ko")
    @shin = size!(@theme, "152mmx225mm", "신국판", 152, 225)
    @a4 = size!(@theme, "210mmx297mm", "A4", 210, 297)
    @kook = size!(@theme, "148mmx210mm", "국판", 148, 210)
    @a4.document_designs.find_by!(doc_type: "chapter").paragraph_styles.create!(name: "body", text_color: "a4-red")
  end

  teardown do
    Design::Theme.where("name LIKE ?", "#{@theme.name}%").find_each do |t|
      File.delete(t.db_path) if File.exist?(t.db_path)
    end
  end

  def size!(theme, size_name, local_name, w, h)
    ps = theme.paper_sizes.create!(size_name:, local_name:, width_mm: w, height_mm: h, allow_another_size: true)
    ps.document_designs.create!(doc_type: "chapter")
    ps
  end

  def run_task(apply: false, split: false)
    Rails.application.load_tasks unless Rake::Task.task_defined?("design:single_size")
    task = Rake::Task["design:single_size"]
    task.reenable
    ENV["APPLY"] = ("1" if apply)
    ENV["SPLIT"] = ("1" if split)
    capture_io { task.invoke }.first
  ensure
    ENV.delete("APPLY")
    ENV.delete("SPLIT")
  end

  test "collapse! keeps the first size and removes the rest with their designs" do
    removed_designs = (@a4.document_designs.ids + @kook.document_designs.ids)

    Design::SingleSize.collapse!(@theme)

    assert_equal [ @shin.id ], @theme.reload.paper_sizes.ids
    assert_empty Design::DocumentDesign.where(id: removed_designs)
  end

  test "collapse! re-exports the theme's .db with its one size" do
    Design::SingleSize.collapse!(@theme)

    db = SQLite3::Database.new(@theme.db_path)
    assert_equal [ [ "152mmx225mm" ] ], db.execute("SELECT size_name FROM paper_sizes")
  ensure
    db&.close
  end

  test "split: each other size first becomes its own design, named for its size" do
    Design::SingleSize.collapse!(@theme, split: true)

    assert_equal [ @shin.id ], @theme.reload.paper_sizes.ids
    a4 = Design::Theme.find_by!(name: "#{@theme.name} A4")
    kook = Design::Theme.find_by!(name: "#{@theme.name} 국판")
    [ a4, kook ].each do |t|
      assert_equal 1, t.paper_sizes.count
      assert t.system?, "the owner carries over"
      assert_equal "ko", t.locale
      assert File.exist?(t.db_path)
    end
    ps = a4.paper_sizes.sole
    assert_equal [ "A4", 210 ], [ ps.local_name, ps.width_mm.to_i ]
    assert_equal "a4-red", ps.document_designs.find_by!(doc_type: "chapter").paragraph_styles.find_by!(name: "body").text_color,
                 "the size's own designs are copied, not the default's"
  end

  test "split: a size without a local name still copies itself" do
    @kook.update!(local_name: nil)
    Design::SingleSize.collapse!(@theme, split: true)

    assert_equal [ [ 148, 210 ] ], Design::Theme.find_by!(name: "#{@theme.name} 148x210").paper_sizes.map { |ps| [ ps.width_mm.to_i, ps.height_mm.to_i ] }
  end

  test "split: a non-Korean theme's copies carry ASCII names" do
    en = Design::Theme.create!(name: "Classic #{SecureRandom.hex(3)}", locale: "en", user: users(:david))
    size!(en, "152mmx225mm", "신국판", 152, 225)
    size!(en, "148mmx210mm", "국판", 148, 210)

    Design::SingleSize.collapse!(en, split: true)

    copy = Design::Theme.find_by!(name: "#{en.name} 148x210")
    assert_equal users(:david), copy.user
  ensure
    Design::Theme.where("name LIKE ?", "#{en.name}%").each { |t| File.delete(t.db_path) if File.exist?(t.db_path) } if en
  end

  test "a one-size theme is left alone" do
    one = Design::Theme.create!(name: "One #{SecureRandom.hex(3)}", locale: "ko")
    size!(one, "152mmx225mm", "신국판", 152, 225)

    assert_nil Design::SingleSize.collapse!(one)
    assert_equal 1, one.paper_sizes.count
    refute File.exist?(one.db_path)
  end

  test "the rake task is a dry run by default" do
    out = run_task

    assert_match(/#{Regexp.escape(@theme.name)}.*keep 신국판/, out)
    assert_match(/remove A4, 국판/, out)
    assert_match(/dry run/i, out)
    assert_equal 3, @theme.paper_sizes.count
  end

  test "APPLY=1 collapses; SPLIT=1 splits first" do
    out = run_task(apply: true, split: true)

    assert_match(/#{Regexp.escape(@theme.name)}/, out)
    assert_equal 1, @theme.paper_sizes.count
    assert Design::Theme.exists?(name: "#{@theme.name} A4")
  end

  test "the rake task skips book designs" do
    book = Design::Theme.create!(name: "Book #{SecureRandom.hex(3)}", locale: "ko", book_id: 9)
    size!(book, "152mmx225mm", "신국판", 152, 225)
    size!(book, "210mmx297mm", "A4", 210, 297)

    out = run_task(apply: true)

    assert_no_match(/#{book.name}/, out)
    assert_equal 2, book.paper_sizes.count
  end

  test "split copies of an ASCII-named theme leave the source's .db its own" do
    classic = Design::Theme.create!(name: "Classic #{SecureRandom.hex(3)}", locale: "ko")
    size!(classic, "152mmx225mm", "신국판", 152, 225)
    size!(classic, "128mmx188mm", "사륙판", 128, 188)

    Design::SingleSize.collapse!(classic, split: true)

    db = SQLite3::Database.new(classic.db_path)
    assert_equal [ classic.name ], db.execute("SELECT name FROM themes").flatten
    copy = Design::Theme.find_by!(name: "#{classic.name} 사륙판")
    assert_not_equal classic.db_path, copy.db_path
  ensure
    db&.close
    Design::Theme.where("name LIKE ?", "#{classic.name}%").each { |t| File.delete(t.db_path) if File.exist?(t.db_path) } if classic
  end

  def sk_first_theme
    theme = Design::Theme.create!(name: "모던 #{SecureRandom.hex(3)}", locale: "ko")
    sk = size!(theme, "128mmx188mm", "사륙판", 128, 188)
    shin = size!(theme, "152mmx225mm", "신국판", 152, 225)
    [ theme, sk, shin ]
  end

  test "collapse! keeps 신국판, the house default, even when it isn't the first size" do
    theme, _sk, shin = sk_first_theme
    assert_equal "keep 신국판", Design::SingleSize.plan(theme).to_s[/keep [^,]+/]

    Design::SingleSize.collapse!(theme)

    assert_equal [ shin.id ], theme.reload.paper_sizes.ids
  ensure
    File.delete(theme.db_path) if theme && File.exist?(theme.db_path)
  end

  test "split: the theme keeps 신국판 and 사륙판 becomes its own design" do
    theme, sk, shin = sk_first_theme

    Design::SingleSize.collapse!(theme, split: true)

    assert_equal [ shin.id ], theme.reload.paper_sizes.ids
    copy = Design::Theme.find_by!(name: "#{theme.name} 사륙판")
    assert_equal [ [ "사륙판", 128 ] ], copy.paper_sizes.map { |ps| [ ps.local_name, ps.width_mm.to_i ] }
    assert_nil Design::Theme.find_by(name: "#{theme.name} 신국판")
    assert_not Design::PaperSize.exists?(sk.id)
  ensure
    Design::Theme.where("name LIKE ?", "#{theme.name}%").each { |t| File.delete(t.db_path) if File.exist?(t.db_path) } if theme
  end
end
