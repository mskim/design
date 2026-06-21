require "test_helper"
require Design::Engine.root.join("lib/design/tailwind_scoper")

class DesignTailwindIsolationTest < ActiveSupport::TestCase
  CSS = Design::Engine.root.join("app/assets/builds/design.css")

  test "built design.css exists and is non-trivial" do
    assert File.exist?(CSS), "run bin/rails design:tailwind:build"
    assert File.size(CSS) > 1000
  end

  test "every style rule is scoped under .design-studio (no host leak)" do
    offenders = Design::TailwindScoper.unscoped_selectors(File.read(CSS), under: ".design-studio")
    assert_empty offenders, "Unscoped selectors would leak onto host pages: #{offenders.first(15).inspect}"
  end

  test "scoper is idempotent and self-consistent on a sample" do
    sample = "*,::before{box-sizing:border-box}:root{--x:1}.flex{display:flex}@keyframes spin{to{transform:rotate(360deg)}}@media (min-width:40rem){.p-4{padding:1rem}}"
    out = Design::TailwindScoper.scope(sample, under: ".design-studio")
    assert_includes out, ".design-studio .flex"
    assert_includes out, "@keyframes spin"          # keyframe name untouched
    assert_includes out, "rotate(360deg)"           # keyframe body untouched
    assert_includes out, ".design-studio .p-4"      # scoped inside @media
    assert_empty Design::TailwindScoper.unscoped_selectors(out, under: ".design-studio")
  end
end
