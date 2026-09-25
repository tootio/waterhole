require "test_helper"

class KeywordRulesTest < ActionDispatch::IntegrationTest
  setup do
    @moderator = sign_in_as moderators(:avery)
    @own   = KeywordRule.create!(instance: instances(:alpha), pattern: "seo", match_type: "word", severity: "warning")
    @other = KeywordRule.create!(instance: instances(:beta), pattern: "casino", match_type: "word", severity: "warning")
  end

  test "a moderator sees only their own instance's rules" do
    get keyword_rules_path

    assert_response :success
    assert_select "code", "seo"
    assert_select "code", { count: 0, text: "casino" }
  end

  test "a moderator can add, edit and delete their own instance's rules" do
    post keyword_rules_path, params: { keyword_rule: { pattern: "giveaway", match_type: "word", severity: "info" } }
    assert_equal instances(:alpha), KeywordRule.find_by!(pattern: "giveaway").instance

    patch keyword_rule_path(@own), params: { keyword_rule: { pattern: "backlinks" } }
    assert_equal "backlinks", @own.reload.pattern

    delete keyword_rule_path(@own)
    refute KeywordRule.exists?(@own.id)
  end

  test "another instance's rules cannot be changed" do
    patch keyword_rule_path(@other), params: { keyword_rule: { pattern: ".*" } }
    assert_response :not_found
    assert_equal "casino", @other.reload.pattern

    delete keyword_rule_path(@other)
    assert_response :not_found
    assert KeywordRule.exists?(@other.id)
  end

  # No deployment-wide rules: one would flag every instance's queue while any
  # instance's moderators could edit it.
  test "a rule must belong to an instance" do
    refute KeywordRule.new(pattern: "airdrop", match_type: "word", severity: "warning").valid?
  end

  test "suggested watchwords show whether this instance applied them" do
    probe, bio = SuggestedWatchword.all
    KeywordRule.create!(instance: instances(:alpha), pattern: probe.pattern, match_type: probe.match_type, severity: "info")
    KeywordRule.create!(instance: instances(:beta), pattern: bio.pattern, match_type: bio.match_type, severity: "warning")

    get keyword_rules_path

    assert_select "section li", count: SuggestedWatchword.all.size
    assert_select "section li p", text: probe.reasoning
    assert_select "section li", text: /#{Regexp.escape(probe.pattern)}.*Applied/m
    assert_select "section a[href=?]", new_keyword_rule_path(keyword_rule: probe.to_params), count: 0
    # Another instance's copy does not count.
    assert_select "section a[href=?]", new_keyword_rule_path(keyword_rule: bio.to_params), text: "Apply"
  end

  test "applying a suggestion opens the form pre-filled" do
    suggestion = SuggestedWatchword.all.first

    get new_keyword_rule_path(keyword_rule: suggestion.to_params)

    assert_response :success
    assert_select "input[name='keyword_rule[pattern]'][value=?]", suggestion.pattern
    assert_select "select[name='keyword_rule[match_type]'] option[selected][value=?]", suggestion.match_type
    assert_select "select[name='keyword_rule[severity]'] option[selected][value=?]", suggestion.severity
    assert_select "input[name='keyword_rule[description]'][value=?]", suggestion.description
  end

  test "moderators are pointed to the issues page to propose a suggestion" do
    get keyword_rules_path
    assert_select "section a[href=?]", "#{Waterhole::Deployment::DEFAULT_SOURCE_URL}/issues/new?template=watchword_suggestion.yml",
      text: "Propose it as a suggestion"

    ENV["WATERHOLE_SOURCE_URL"] = "https://codeberg.org/someone/waterhole"
    get keyword_rules_path
    assert_select "section a", { count: 0, text: "Propose it as a suggestion" }

    ENV["WATERHOLE_ISSUES_URL"] = "https://codeberg.org/someone/waterhole/issues"
    get keyword_rules_path
    assert_select "section a[href=?]", "https://codeberg.org/someone/waterhole/issues"
  ensure
    ENV.delete("WATERHOLE_SOURCE_URL")
    ENV.delete("WATERHOLE_ISSUES_URL")
  end
end
