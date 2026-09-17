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
end
