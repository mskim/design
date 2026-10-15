source "https://rubygems.org"

# Specify the gem's dependencies in design.gemspec
# (rails, phlex-rails, designcraft_rb, hexapdf, sqlite3).
gemspec

# designcraft_rb lays the previews out; sourced from GitHub (not on RubyGems), as the
# hosts do. Locally overridden via .bundle/config (BUNDLE_LOCAL__DESIGNCRAFT_RB).
gem "designcraft_rb", github: "mskim/designcraft_rb", branch: "main", require: false

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
