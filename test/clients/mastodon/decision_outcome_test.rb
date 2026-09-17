require "test_helper"

# Mastodon returns the same 403 body whether the account is no longer pending or
# the moderator's role lacks "Manage Users". Every branch here exists because the
# status code alone cannot tell them apart.
class Mastodon::DecisionOutcomeTest < ActiveSupport::TestCase
  setup do
    @instance = instances(:alpha)
    @client = Mastodon::Client.new(base_url: @instance.base_url, access_token: "t")
  end

  test "an account that reads back as approved means someone else approved it" do
    stub_admin_account(@instance, id: 9, body: { "id" => "9", "approved" => true })

    outcome = Mastodon::DecisionOutcome.resolve(@client, 9)

    assert outcome.conflict?
    assert_equal "approved_elsewhere", outcome.status
  end

  test "a 404 means it was rejected, because rejection deletes the user" do
    stub_admin_account(@instance, id: 9, status: 404, body: { "error" => "Record not found" })

    outcome = Mastodon::DecisionOutcome.resolve(@client, 9)

    assert outcome.conflict?
    assert_equal "rejected_elsewhere", outcome.status
  end

  test "a 404 for an account that never confirmed reports expiry, not someone's rejection" do
    stub_admin_account(@instance, id: 9, status: 404, body: { "error" => "Record not found" })

    outcome = Mastodon::DecisionOutcome.resolve(@client, 9, gone_status: "expired")

    assert outcome.conflict?
    assert_equal "expired", outcome.status
    assert_match(/never confirmed/, outcome.message)
  end

  test "an account still pending means the moderator lacks the role" do
    stub_admin_account(@instance, id: 9, body: { "id" => "9", "approved" => false })

    outcome = Mastodon::DecisionOutcome.resolve(@client, 9)

    refute outcome.conflict?
    assert_equal :failed, outcome.kind
    assert_match(/Manage Users/, outcome.message)
  end

  test "a second 403 means the token cannot even read, and is reported as such" do
    stub_admin_account(@instance, id: 9, status: 403, body: { "error" => "This action is not allowed" })

    outcome = Mastodon::DecisionOutcome.resolve(@client, 9)

    refute outcome.conflict?
    assert_equal :failed, outcome.kind
  end
end
