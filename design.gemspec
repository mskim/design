require_relative "lib/design/version"

Gem::Specification.new do |spec|
  spec.name        = "design"
  spec.version     = Design::VERSION
  spec.authors     = [ "mskim" ]
  spec.email       = [ "mskimsid@gmail.com" ]
  spec.homepage    = "https://github.com/mskim/design"
  spec.summary     = "Shared book design studio engine (themes, paper sizes, paragraph styles)"
  spec.description = "A mountable Rails engine providing the BookWrite/BookDesign theme editor: " \
                     "Design:: models on design_* tables, Phlex + scoped-Tailwind UI, and the " \
                     "ThemeDbExportService / ThemeImportService theme-transfer pipeline."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  # RubyUI is vendored as Phlex components under app/components/ruby_ui (not a gem).
  spec.add_dependency "rails", ">= 8.1.2"
  spec.add_dependency "phlex-rails"
  spec.add_dependency "doc_processor_rb"
  spec.add_dependency "sqlite3"
end
