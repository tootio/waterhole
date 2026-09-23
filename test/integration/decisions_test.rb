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

  # Regression: a 404 used to escape as a 500 page, and as an "expected"
  # Mastodon error it never reached the error tracker either.
  test "an account deleted before the decision is a conflict, not a crash" do
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "approve", status: 404,
      body: { "error" => "Record not found" })

    post registration_request_decision_path(@pending, decision_action: "approve")

    assert_redirected_to registration_request_path(@pending)
    assert_equal "rejected_elsewhere", @pending.reload.status
    assert @pending.decision.state_conflict?
    assert_match(/Already rejected in Mastodon/, flash[:alert])
  end

  test "an unconfirmed account Mastodon cleaned up reads as expired" do
    @pending.update_columns(confirmed: false, signed_up_at: (RegistrationRequest::UNCONFIRMED_ACCOUNT_LIFETIME + 1.day).ago)
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "reject", status: 404,
      body: { "error" => "Record not found" })

    post registration_request_decision_path(@pending, decision_action: "reject")

    assert_equal "expired", @pending.reload.status
    assert_match(/never confirmed/, flash[:alert])
  end

  test "an undocumented 422 fails the decision instead of crashing" do
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "approve", status: 422,
      body: { "error" => "Validation failed" })

    post registration_request_decision_path(@pending, decision_action: "approve")

    assert_redirected_to registration_request_path(@pending)
    assert @pending.decision.reload.state_failed?
    assert_equal "pending", @pending.reload.status
    assert_match(/Validation failed/, flash[:alert])
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

  test "approve and advance redirects to the next request in the list, not back to this one" do
    claimed_alpha = registration_requests(:claimed_alpha) # next after pending_alpha, newest first
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "approve")

    post registration_request_decision_path(@pending, decision_action: "approve", advance: 1)

    assert_equal "approved", @pending.reload.status
    assert_redirected_to registration_request_path(claimed_alpha)
  end

  test "approve and advance on the last request in the list falls back to the queue" do
    jules_alpha = registration_requests(:jules_alpha) # last in the default (newest-first, pending) list
    stub_decision(@instance, id: jules_alpha.mastodon_account_id, action: "approve")

    post registration_request_decision_path(jules_alpha, decision_action: "approve", advance: 1)

    assert_equal "approved", jules_alpha.reload.status
    assert_redirected_to registration_requests_path
  end

  test "a plain approve without advance still redirects back to this request" do
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "approve")

    post registration_request_decision_path(@pending, decision_action: "approve")

    assert_redirected_to registration_request_path(@pending)
  end

  # Regression: the "→" buttons used to link to decision_action/advance only,
  # dropping whatever filter the moderator was actually viewing. The neighbor
  # lookup on the next request then ran against the *default* filter instead,
  # so it usually missed and fell back to the plain, unfiltered queue instead
  # of the next item the moderator was actually working through.
  test "the approve/reject and next buttons carry the active filter and sort along" do
    jules_alpha = registration_requests(:jules_alpha) # oldest of the three pending alpha requests

    get registration_request_path(jules_alpha, sort: "oldest")

    assert_response :success
    assert_select "form[data-detail-nav-target=approveAndNextForm]" do |forms|
      assert_match(/sort=oldest/, forms.first["action"])
    end
    assert_select "form[data-detail-nav-target=rejectAndNextForm]" do |forms|
      assert_match(/sort=oldest/, forms.first["action"])
    end
  end

  test "reject and advance follows the filter carried on the button, landing on the right next request" do
    jules_alpha   = registration_requests(:jules_alpha)   # oldest, so first under sort: oldest
    claimed_alpha = registration_requests(:claimed_alpha) # next after jules_alpha under sort: oldest
    stub_decision(@instance, id: jules_alpha.mastodon_account_id, action: "reject")

    post registration_request_decision_path(jules_alpha, decision_action: "reject", advance: 1, sort: "oldest")

    assert_equal "rejected", jules_alpha.reload.status
    assert_redirected_to registration_request_path(claimed_alpha, sort: "oldest")
  end

  # --- JSON, for the queue page's bulk actions (bulk_select_controller.js) ---

  test "json: a successful decision answers with the outcome and Mastodon's rate-limit budget" do
    stub_request(:post, "#{@instance.base_url}/api/v1/admin/accounts/#{@pending.mastodon_account_id}/reject")
      .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json",
        "X-RateLimit-Remaining" => "42", "X-RateLimit-Reset" => 3.minutes.from_now.iso8601 })

    post registration_request_decision_path(@pending, decision_action: "reject"), as: :json

    assert_response :ok
    assert_equal "rejected", @pending.reload.status
    assert_equal "succeeded", response.parsed_body["outcome"]
    assert_equal @pending.username, response.parsed_body["username"]
    assert_equal 42, response.parsed_body.dig("rate_limit", "remaining")
    assert response.parsed_body.dig("rate_limit", "reset_at").present?
  end

  test "json: a 429 queues the decision and says how long to back off" do
    stub_decision_rate_limited(@instance, id: @pending.mastodon_account_id, action: "reject", reset_at: 30.seconds.from_now)

    assert_enqueued_with(job: PushDecisionJob) do
      post registration_request_decision_path(@pending, decision_action: "reject"), as: :json
    end

    assert_response :accepted
    assert_equal "queued", response.parsed_body["outcome"]
    assert_in_delta 30, response.parsed_body["retry_after"], 2
    assert_equal 0, response.parsed_body.dig("rate_limit", "remaining")
    assert @pending.reload.decision.state_pending?
  end

  test "json: Mastodon being unreachable is queued without a retry_after" do
    stub_request(:post, "#{@instance.base_url}/api/v1/admin/accounts/#{@pending.mastodon_account_id}/reject").to_timeout

    post registration_request_decision_path(@pending, decision_action: "reject"), as: :json

    assert_response :accepted
    assert_equal "queued", response.parsed_body["outcome"]
    assert_nil response.parsed_body["retry_after"]
  end

  test "json: a conflict is a 409" do
    stub_decision_forbidden(@instance, id: @pending.mastodon_account_id)
    stub_admin_account(@instance, id: @pending.mastodon_account_id,
      body: { "id" => @pending.mastodon_account_id, "approved" => true })

    post registration_request_decision_path(@pending, decision_action: "approve"), as: :json

    assert_response :conflict
    assert_equal "conflict", response.parsed_body["outcome"]
    assert_match(/Already approved/, response.parsed_body["message"])
  end

  test "json: an already-resolved request is a 409 and never reaches Mastodon" do
    @pending.update!(status: "rejected", resolved_at: Time.current)

    post registration_request_decision_path(@pending, decision_action: "reject"), as: :json

    assert_response :conflict
    assert_equal "already_resolved", response.parsed_body["outcome"]
    assert_nil @pending.reload.decision
  end

  test "json: an unknown action is a 422" do
    post registration_request_decision_path(@pending, decision_action: "banish"), as: :json

    assert_response :unprocessable_content
    assert_equal "failed", response.parsed_body["outcome"]
  end

  test "json: a dead token is a 401, so the bulk loop stops" do
    stub_decision(@instance, id: @pending.mastodon_account_id, action: "reject", status: 401,
      body: { "error" => "The access token is invalid" })

    post registration_request_decision_path(@pending, decision_action: "reject"), as: :json

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body["outcome"]
  end
end
