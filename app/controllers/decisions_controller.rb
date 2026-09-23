# Pushes the decision to Mastodon INLINE rather than queueing it: the moderator
# is standing right there, it is a single POST, and the conflict case needs to be
# on screen immediately rather than discovered later.
#
# Only a transport failure falls back to a background retry.
#
# Also answers JSON, for the queue page's bulk actions: one request per
# registration, run from the browser (bulk_select_controller.js), which is how a
# wave of fifty rejections avoids one server request that outlives its timeout.
# The JSON carries Mastodon's rate-limit budget so that loop can pace itself.
class DecisionsController < ApplicationController
  include RegistrationRequestFilters

  PUSH_TIMEOUT = 10

  OUTCOME_STATUS = {
    "succeeded" => :ok,
    "queued" => :accepted,
    "conflict" => :conflict,
    "failed" => :unprocessable_content,
    "unauthorized" => :unauthorized
  }.freeze

  before_action :set_registration_request

  def create
    action = params[:decision_action].to_s
    return refuse("failed", "Unknown action.", :unprocessable_content) unless Decision::ACTIONS.include?(action)

    if @registration_request.resolved?
      return refuse("already_resolved", "This request is already #{@registration_request.status.humanize.downcase}.", :conflict)
    end

    advance = params[:advance].present?
    # Looked up before push() changes @registration_request's status, so it's
    # still found in a status-filtered list like the default "pending" queue.
    next_request = RegistrationRequests::Neighbors.new(filtered_registration_requests, @registration_request).after if advance

    decision = build_decision(action)
    return refuse("failed", decision.errors.full_messages.to_sentence, :unprocessable_content) unless decision.persisted?

    push(decision)

    respond_to do |format|
      format.html do
        if advance
          redirect_to (next_request ? registration_request_path(next_request, filter_params) : registration_requests_path(filter_params)),
            **(@flash || {})
        else
          redirect_back_or_to path, **(@flash || {})
        end
      end
      format.json { render json: result_json, status: OUTCOME_STATUS.fetch(@outcome) }
    end
  end

  private

  def set_registration_request
    @registration_request = registration_requests_scope.find(params[:registration_request_id])
  end

  def path = registration_request_path(@registration_request)

  # The early exits, before anything reached Mastodon.
  def refuse(outcome, message, status)
    respond_to do |format|
      format.html { redirect_back_or_to path, alert: message }
      format.json { render json: result_json(outcome:, message:), status: }
    end
  end

  # rate_limit is only known once Mastodon answered; retry_after only when it
  # answered 429, which is how the bulk loop tells "slow down" from "down".
  def result_json(outcome: @outcome, message: @flash&.values&.first)
    {
      id: @registration_request.id,
      username: @registration_request.username,
      outcome:,
      message:,
      retry_after: @retry_after&.to_f&.ceil,
      rate_limit: @client && { remaining: @client.rate_limit_remaining, reset_at: @client.rate_limit_reset_at&.iso8601 }
    }.compact
  end

  # One decision row per request -- the unique index is the double-submit guard.
  #
  # An existing row is REUSED rather than rejected, so a push that failed or is
  # stuck can be tried again. Creating a second one would trip the uniqueness
  # validation and leave the moderator unable to act on their own queue item at
  # all. (A decision that already succeeded is unreachable here: the request is
  # resolved by then, and #create returns earlier.)
  def build_decision(action)
    decision = @registration_request.decision || Decision.new(registration_request: @registration_request)
    decision.assign_attributes(moderator: current_moderator, action: action,
      state: "pending", error_message: nil)
    decision.save
    decision
  end

  def push(decision)
    client.public_send(decision.approve? ? :approve_account : :reject_account,
      @registration_request.mastodon_account_id)

    decision.update!(state: "succeeded", performed_at: Time.current,
      attempts: decision.attempts + 1)
    @registration_request.update!(status: decision.resolved_status, resolved_at: Time.current)
    @outcome = "succeeded"
    @flash = { notice: "#{decision.resolved_status.capitalize} @#{@registration_request.username}." }
  rescue Mastodon::Forbidden
    handle_forbidden(decision)
  rescue Mastodon::NotFound
    # The account vanished before the decision reached it.
    apply_outcome(decision, Mastodon::DecisionOutcome.gone(@registration_request.deleted_upstream_status))
  rescue Mastodon::Unprocessable => e
    # Not an answer Mastodon documents for approve/reject. Keep the moderator on
    # the page, and tell whoever runs this Waterhole.
    Rails.error.report(e, handled: true)
    decision.update!(state: "failed", error_message: e.message)
    @outcome = "failed"
    @flash = { alert: "Mastodon rejected this action: #{e.message}" }
  rescue Mastodon::Unauthorized => e
    current_moderator.invalidate_token!
    decision.update!(state: "failed", error_message: e.message)
    @outcome = "unauthorized"
    @flash = { alert: "Your Mastodon token was rejected. Please sign in again." }
  rescue Mastodon::ConnectionError, Mastodon::ServerError, Mastodon::RateLimited => e
    # Transport, not judgement: keep the decision and retry in the background.
    decision.update!(state: "pending", error_message: e.message, attempts: decision.attempts + 1)
    PushDecisionJob.perform_later(decision)
    @outcome = "queued"
    @retry_after = e.retry_after if e.is_a?(Mastodon::RateLimited)
    @flash = { notice: "#{@registration_request.username} queued -- Mastodon is not responding, retrying in the background." }
  end

  # 403 is ambiguous: "no longer pending" and "your role can't do this" are
  # indistinguishable by status code, so read the account back to find out which.
  def handle_forbidden(decision)
    apply_outcome(decision, Mastodon::DecisionOutcome.resolve(client, @registration_request.mastodon_account_id,
      gone_status: @registration_request.deleted_upstream_status))
  end

  def apply_outcome(decision, outcome)
    if outcome.conflict?
      decision.update!(state: "conflict", error_message: outcome.message)
      @registration_request.update!(status: outcome.status, resolved_at: Time.current)
      @registration_request.broadcast_refresh_later
      @outcome = "conflict"
      @flash = { alert: outcome.message }
    else
      decision.update!(state: "failed", error_message: outcome.message)
      @outcome = "failed"
      @flash = { alert: outcome.message }
    end
  end

  def client
    @client ||= Mastodon::Client.new(base_url: current_instance.base_url,
      access_token: current_moderator.access_token, read_timeout: PUSH_TIMEOUT)
  end
end
