require "test_helper"

class SuggestedWatchwordTest < ActiveSupport::TestCase
  test "every suggestion makes a valid rule" do
    SuggestedWatchword.all.each do |suggestion|
      rule = KeywordRule.new(instance: instances(:alpha), **suggestion.to_params)
      assert rule.valid?, "#{suggestion.pattern}: #{rule.errors.full_messages.to_sentence}"
    end
  end

  test "every suggestion explains itself" do
    SuggestedWatchword.all.each { assert it.reasoning.present?, "#{it.pattern} has no reasoning" }
  end

  test "the suggested patterns match what they are meant to" do
    probe, bio = SuggestedWatchword.all.map { KeywordRule.new(**it.to_params) }

    assert probe.matches?("Automated protocol deliverability probe")
    refute probe.matches?("Automated protocol deliverability probe, and a real person")

    assert bio.matches?("I write software and poetry.")
    refute bio.matches?("I write and read.")
  end

  test "a suggestion is applied when a rule has the same pattern and match type" do
    suggestion = SuggestedWatchword.all.first
    same = KeywordRule.new(pattern: suggestion.pattern, match_type: suggestion.match_type, severity: "info")
    other_type = KeywordRule.new(pattern: suggestion.pattern, match_type: "substring")

    assert suggestion.applied?([ same ])
    refute suggestion.applied?([ other_type ])
  end
end
