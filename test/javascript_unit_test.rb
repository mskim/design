require "test_helper"
require "shellwords"

# Pure JS helpers (no DOM) are tested with Node's built-in runner. Skips when node is
# not installed so the Ruby suite stays runnable anywhere.
class DesignJavascriptUnitTest < ActiveSupport::TestCase
  test "pure JS helper suites pass under node --test" do
    node = `command -v node`.strip
    skip "node is not installed" if node.empty?
    files = Dir[Design::Engine.root.join("test/javascript/*.test.mjs").to_s]
    assert files.any?, "no JS test files found"
    output = `#{Shellwords.escape(node)} --test #{files.map { |f| Shellwords.escape(f) }.join(" ")} 2>&1`
    assert $?.success?, output
  end
end
