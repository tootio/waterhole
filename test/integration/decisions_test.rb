require "test_helper"

class DecisionsTest < ActionDispatch::IntegrationTest
  setup do
    @moderator = moderators(:avery)
    @pending = registration_requests(:pending_alpha)
    @instance = instances(:alpha)
    sign_in_as @moderator
  end

  test "approving pushes to Mastodon and records who decided" do
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "approve")

    post registration_request_decision_path(@pending, decision_action: "approve")

    assert_equal "approved", @pending.reload.status
    decision = @pending.decision
    assert decision.state_succeeded?
    assert_equal @moderator, decision.moderator
  end

  test "rejecting pushes to Mastodon" do
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "reject")

    post registration_request_decision_path(@pending, decision_action: "reject")

    assert_equal "rejected", @pending.reload.status
  end

  # Mastodon's 403 means either "already actioned" or "you lack the role", and
  # the difference matters enormously to the moderator reading the screen.
  test "a 403 on an account that reads back approved is a conflict, not a failure" do
    stub_decision_forbidden(@instance, id: @pending.mastodon_account_id)
    stub_admin_account(@instance, id: @pending.mastodon_account_id,
      body: { "id" => @pending.mastodon_account_id, "approved" => true })

    post registration_request_decision_path(@pending, decision_action: "approve")

    assert_equal "approved_elsewhere", @pending.reload.status
    assert @pending.decision.state_conflict?
    assert_match(/Already approved/, flash[:alert])
  end

  test "a 403 on an account still pending is reported as a permissions problem" do
    stub_decision_forbidden(@instance, id: @pending.mastodon_account_id)
    stub_admin_account(@instance, id: @pending.mastodon_account_id,
      body: { "id" => @pending.mastodon_account_id, "approved" => false })

    post registration_request_decision_path(@pending, decision_action: "approve")

    assert_equal "pending", @pending.reload.status, "nothing happened upstream, so nothing should change here"
    assert @pending.decision.state_failed?
    assert_match(/Manage Users/, flash[:alert])
  end

  test "a network failure queues a retry rather than losing the decision" do
    stub_request(:post, "#{@instance.base_url}/api/v1/admin/accounts/#{@pending.mastodon_account_id}/approve")
      .to_timeout

    assert_enqueued_with(job: PushDecisionJob) do
      post registration_request_decision_path(@pending, decision_action: "approve")
    end

    assert @pending.decision.state_pending?
    assert_equal "pending", @pending.reload.status
  end

  # Without this the second press hits the uniqueness validation, returns an
  # unsaved record, and the moderator is locked out of their own queue item with
  # "has already been taken".
  test "a decision whose push failed can be tried again" do
    stub_request(:post, "#{@instance.base_url}/api/v1/admin/accounts/#{@pending.mastodon_account_id}/approve")
      .to_timeout
    post registration_request_decision_path(@pending, decision_action: "approve")
    assert @pending.reload.decision.state_pending?

    # Mastodon is back.
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "approve")
    post registration_request_decision_path(@pending, decision_action: "approve")

    assert_equal "approved", @pending.reload.status
    assert @pending.decision.state_succeeded?
    assert_equal 1, Decision.where(registration_request: @pending).count,
      "retrying must reuse the decision row, not try to create a second one"
  end

  test "a moderator can switch a stuck approve to a reject" do
    stub_request(:post, "#{@instance.base_url}/api/v1/admin/accounts/#{@pending.mastodon_account_id}/approve")
      .to_timeout
    post registration_request_decision_path(@pending, decision_action: "approve")

    stub_decision(@instance, id: @pending.mastodon_account_id, action: "reject")
    post registration_request_decision_path(@pending, decision_action: "reject")

    assert_equal "rejected", @pending.reload.status
  end

  test "an already-resolved request cannot be decided again" do
    @pending.update!(status: "approved", resolved_at: Time.current)

    post registration_request_decision_path(@pending, decision_action: "reject")

    assert_nil @pending.reload.decision
    assert_match(/already/, flash[:alert])
  end

  test "an unknown action is refused" do
    post registration_request_decision_path(@pending, decision_action: "banish")

    assert_nil @pending.reload.decision
  end
end
