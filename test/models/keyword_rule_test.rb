require "test_helper"

class KeywordRuleTest < ActiveSupport::TestCase
  setup do
    @instance = instances(:alpha)
  end

  # --- matches? --------------------------------------------------------------

  test "substring match is case-insensitive and matches anywhere in text" do
    rule = KeywordRule.new(instance: @instance, pattern: "crypto", match_type: "substring")

    assert rule.matches?("I love CRYPTO news")
    assert rule.matches?("cryptography is interesting")
    refute rule.matches?("hello world")
    refute rule.matches?("")
    refute rule.matches?(nil)
  end

  test "word match is case-insensitive and respects word boundaries" do
    rule = KeywordRule.new(instance: @instance, pattern: "seo", match_type: "word")

    assert rule.matches?("Looking for SEO services")
    assert rule.matches?("SEO is great")
    refute rule.matches?("museum of seoul")
    refute rule.matches?("")
    refute rule.matches?(nil)
  end

  test "regex match matches valid regular expressions with timeout" do
    rule = KeywordRule.new(instance: @instance, pattern: 'https?://\S+', match_type: "regex")

    assert rule.matches?("Check https://example.com/join")
    refute rule.matches?("no link here")
  end

  # --- match_indices ---------------------------------------------------------

  test "match_indices returns empty array when blank or nil" do
    rule = KeywordRule.new(instance: @instance, pattern: "test", match_type: "word")

    assert_equal [], rule.match_indices(nil)
    assert_equal [], rule.match_indices("")
  end

  test "match_indices with substring returns start and stop indices of all matches" do
    rule = KeywordRule.new(instance: @instance, pattern: "air", match_type: "substring")
    indices = rule.match_indices("AIRDROP and fresh air and upstairs")

    assert_equal [ [ 0, 3 ], [ 18, 21 ], [ 30, 33 ] ], indices
  end

  test "match_indices with word returns start and stop indices of full word matches" do
    rule = KeywordRule.new(instance: @instance, pattern: "cat", match_type: "word")
    indices = rule.match_indices("catalog cat bobcat CAT")

    assert_equal [ [ 8, 11 ], [ 19, 22 ] ], indices
  end

  test "match_indices with regex returns start and stop indices of regex matches" do
    rule = KeywordRule.new(instance: @instance, pattern: 'https?://\S+', match_type: "regex")
    indices = rule.match_indices("Visit https://example.com/join for info")

    assert_equal [ [ 6, 30 ] ], indices
  end

  test "match_indices handles invalid regex gracefully" do
    rule = KeywordRule.new(instance: @instance, pattern: "[invalid", match_type: "regex")
    indices = rule.match_indices("some text")

    assert_equal [], indices
  end
end
