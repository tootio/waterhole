require "test_helper"

class PushDecisionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @instance = instances(:alpha)
    @pending = registration_requests(:pending_alpha)
    @decision = Decision.create!(registration_request: @pending, moderator: moderators(:avery),
      action: "approve", state: "pending")
  end

  test "pushes a queued decision when Mastodon comes back" do
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "approve")

    PushDecisionJob.perform_now(@decision)

    assert @decision.reload.state_succeeded?
    assert_equal "approved", @pending.reload.status
  end

  # Without recording the give-up the decision sits in "pending" forever while
  # the UI keeps telling the moderator it is still being retried.
  test "records a failure once retries are exhausted instead of leaving it pending" do
    stub_request(:post, "#{@instance.base_url}/api/v1/admin/accounts/#{@pending.mastodon_account_id}/approve")
      .to_timeout

    perform_enqueued_jobs(only: PushDecisionJob) do
      PushDecisionJob.perform_later(@decision)
    end

    @decision.reload
    assert @decision.state_failed?, "an exhausted retry must not look like one still in flight"
    assert_match(/Gave up/, @decision.error_message)
    assert_equal "pending", @pending.reload.status, "nothing happened upstream, so the request stays pending"
  end

  test "a 403 mid-retry is disambiguated like an inline decision" do
    stub_decision_forbidden(@instance, id: @pending.mastodon_account_id)
    stub_admin_account(@instance, id: @pending.mastodon_account_id,
      body: { "id" => @pending.mastodon_account_id, "approved" => true })

    PushDecisionJob.perform_now(@decision)

    assert @decision.reload.state_conflict?
    assert_equal "approved_elsewhere", @pending.reload.status
  end

  test "an account deleted while the push was queued is a conflict" do
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "approve", status: 404,
      body: { "error" => "Record not found" })

    PushDecisionJob.perform_now(@decision)

    assert @decision.reload.state_conflict?
    assert_equal "rejected_elsewhere", @pending.reload.status
  end

  test "does nothing for a decision that already finished" do
    @decision.update!(state: "succeeded")

    assert_nothing_raised { PushDecisionJob.perform_now(@decision) }
  end
end
