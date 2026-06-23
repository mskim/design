require "test_helper"
require "yaml"

class LocaleParityTest < ActiveSupport::TestCase
  def flatten(h, prefix = "")
    h.flat_map { |k, v| v.is_a?(Hash) ? flatten(v, "#{prefix}#{k}.") : ["#{prefix}#{k}"] }
  end

  test "ko.yml and en.yml have identical design.* key sets" do
    root = Design::Engine.root.join("config/locales")
    ko = flatten(YAML.load_file(root.join("ko.yml")).dig("ko", "design") || {}).sort
    en = flatten(YAML.load_file(root.join("en.yml")).dig("en", "design") || {}).sort
    assert_equal en, ko, "ko/en key mismatch: only-en=#{(en-ko).inspect} only-ko=#{(ko-en).inspect}"
  end
end
