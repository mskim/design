namespace :design do
  desc "Compact doc-type paragraph styles to only the fields that differ from their parent, for every theme"
  task normalize_paragraph_styles: :environment do
    Design::Theme.find_each do |theme|
      Design::ParagraphStyleNormalizer.call(theme)
      puts "normalised #{theme.name}"
    end
  end
end
