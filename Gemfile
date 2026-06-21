source "https://rubygems.org"

# Specify the gem's dependencies in design.gemspec
# (rails, phlex-rails, doc_processor_rb, sqlite3).
gemspec

# doc_processor_rb is sourced from GitHub (not on RubyGems). Locally it is
# overridden via .bundle/config (BUNDLE_LOCAL__DOC_PROCESSOR_RB), mirroring
# book_write — see .bundle/config in this gem.
gem "doc_processor_rb", github: "mskim/doc_processor_rb", branch: "main"

# Bundled stdlib gems doc_processor_rb requires (default gems in Ruby 3.4+).
gem "csv"
gem "ostruct"

# Dummy test app runtime.
gem "puma", ">= 5.0"
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "bcrypt", "~> 3.1.7"

# Phlex (the engine's UI layer) is a gemspec dependency, but Bundler.require
# only auto-requires Gemfile gems — declare it here so `Phlex` is loaded before
# the engine's design.ruby_ui initializer references Phlex::Kit.
gem "phlex-rails"

# Scoped-Tailwind build freshness test shells out to the standalone binary.
# Pin to the exact version book_write built the committed app/assets/builds/design.css
# with — newer binaries emit byte-different CSS, which would fail the freshness
# test spuriously (the committed artifact is fine; only the binary drifted).
gem "tailwindcss-ruby", "= 4.3.0"

# Image variants for Active Storage previews (Design::DocumentDesign heading_bg_image).
gem "image_processing", "~> 1.13"

group :development, :test do
  gem "rubocop-rails-omakase", require: false
end
