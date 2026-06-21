require "test_helper"

class DesignPathHygieneTest < ActiveSupport::TestCase
  test "engine has no hardcoded bookcheego or /Users/Shared paths" do
    root = Rails.root.join("engines", "design")
    offenders = Dir[root.join("**/*.rb")].reject { |f| f == __FILE__ }.select do |f|
      File.read(f).match?(%r{bookcheego|/Users/Shared})
    end
    assert_empty offenders, "Hardcoded paths in design engine: #{offenders.join(', ')}"
  end
end
