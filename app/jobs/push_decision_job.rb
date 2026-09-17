# Retry path only. The happy path is inline in DecisionsController, because the
# moderator is waiting for the answer.
class PushDecisionJob < ApplicationJob
  queue_as :default

  # The blocks matter: without them an exhausted retry just re-raises and the
  # decision sits in "pending" forever while the UI keeps promising it is being
  # retried. A moderator has no way to tell a slow push from a dead one.
  retry_on Mastodon::ConnectionError, Mastodon::ServerError,
    wait: :polynomially_longer, attempts: 6 do |job, error|
    PushDecisionJob.give_up(job, error)
  end
  retry_on Mastodon::RateLimited, attempts: 3,
    wait: ->(_job, error) { error.retry_after } do |job, error|
    PushDecisionJob.give_up(job, error)
  end

  def self.give_up(job, error)
    decision = job.arguments.first
    return unless decision.respond_to?(:state_pending?) && decision.state_pending?

    decision.update(state: "failed",
      error_message: "Gave up after #{job.executions} attempts: #{error.message}")
    decision.registration_request.broadcast_refresh_later
  end

  def perform(decision)
    return unless decision.state_pending?

    request = decision.registration_request
    client = Mastodon::Client.new(base_url: request.instance.base_url,
      access_token: decision.moderator.access_token)

    client.public_send(decision.approve? ? :approve_account : :reject_account,
      request.mastodon_account_id)

    decision.update!(state: "succeeded", performed_at: Time.current, attempts: decision.attempts + 1)
    request.update!(status: decision.resolved_status, resolved_at: Time.current)
  rescue Mastodon::Forbidden
    apply_outcome(decision, request, Mastodon::DecisionOutcome.resolve(client, request.mastodon_account_id,
      gone_status: request.deleted_upstream_status))
  rescue Mastodon::NotFound
    # The account vanished before the decision reached it.
    apply_outcome(decision, request, Mastodon::DecisionOutcome.gone(request.deleted_upstream_status))
  rescue Mastodon::Unprocessable => e
    Rails.error.report(e, handled: true)
    decision.update!(state: "failed", error_message: e.message)
  rescue Mastodon::Unauthorized => e
    decision.moderator.invalidate_token!
    decision.update!(state: "failed", error_message: e.message)
  end

  private

  def apply_outcome(decision, request, outcome)
    if outcome.conflict?
      decision.update!(state: "conflict", error_message: outcome.message)
      request.update!(status: outcome.status, resolved_at: Time.current)
    else
      decision.update!(state: "failed", error_message: outcome.message)
    end
  end
end
