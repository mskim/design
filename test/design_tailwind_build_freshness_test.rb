require "test_helper"
require Design::Engine.root.join("lib/design/tailwind_scoper")

class DesignTailwindBuildFreshnessTest < ActiveSupport::TestCase
  test "committed design.css matches a fresh build" do
    require "tailwindcss/ruby"
    exe = Tailwindcss::Ruby.executable.to_s
    skip "tailwindcss binary unavailable" unless File.exist?(exe)
    root = Design::Engine.root
    Dir.mktmpdir do |dir|
      raw = File.join(dir, "raw.css")
      system(exe, "-i", root.join("app/assets/tailwind/design.css").to_s, "-o", raw, "--minify", exception: true)
      fresh = Design::TailwindScoper.scope(File.read(raw), under: ".design-studio")
      committed = File.read(root.join("app/assets/builds/design.css"))
      assert_equal committed, fresh, "design.css is stale — run `bin/rails design:tailwind:build` and commit"
    end
  end
end
