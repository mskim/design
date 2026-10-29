namespace :design do
  desc "Compact doc-type paragraph styles to only the fields that differ from their parent, for every theme"
  task normalize_paragraph_styles: :environment do
    Design::Theme.starter_themes.find_each do |theme|
      Design::ParagraphStyleNormalizer.call(theme)
      puts "normalised #{theme.name}"
    end
  end
end

namespace :design do
  desc "Give every starter theme one paper size, its first (dry run unless APPLY=1; SPLIT=1 makes each other size its own design first)"
  task single_size: :environment do
    apply = ENV["APPLY"] == "1"
    split = ENV["SPLIT"] == "1"
    # Book designs are copied with one size already.
    plans = Design::Theme.starter_themes.order(:id).filter_map { |theme| Design::SingleSize.plan(theme, split: split) }
    plans.each do |plan|
      Design::SingleSize.collapse!(plan.theme, split: split) if apply
      puts "#{apply ? "collapsed" : "would collapse"} #{plan}"
    end
    puts "#{plans.size} theme(s) with more than one paper size."
    puts "Dry run: nothing changed. Run with APPLY=1 to apply (SPLIT=1 to keep each other size as its own design)." unless apply
  end
end
