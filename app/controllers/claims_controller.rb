# Claiming is what stops two moderators working the same request, so it has to
# be race-proof: a conditional UPDATE, not read-then-write.
class ClaimsController < ApplicationController
  before_action :set_registration_request

  def create
    if claim_atomically || stealing_allowed?
      broadcast_change
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back_or_to registration_request_path(@registration_request) }
      end
    else
      respond_to do |format|
        format.turbo_stream
        format.html do
          redirect_back_or_to registration_request_path(@registration_request),
            alert: "#{@registration_request.reload.claimed_by&.name || "Someone else"} claimed this first."
        end
      end
    end
  end

  def destroy
    @registration_request.update!(claimed_by: nil, claimed_at: nil)
    broadcast_change
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back_or_to registration_request_path(@registration_request) }
    end
  end

  private

  def set_registration_request
    @registration_request = registration_requests_scope.find(params[:registration_request_id])
  end

  # Returns true only if THIS request is the one that took the claim.
  def claim_atomically
    RegistrationRequest
      .where(id: @registration_request.id, claimed_by_id: nil)
      .update_all(claimed_by_id: current_moderator.id, claimed_at: Time.current) == 1
  end

  # Stealing is explicit and only allowed once a claim has gone stale, so it
  # cannot happen by accident.
  def stealing_allowed?
    return false unless params[:force].present? && @registration_request.reload.claim_stale?

    @registration_request.update!(claimed_by: current_moderator, claimed_at: Time.current)
  end

  # update_all skips callbacks, so the broadcast is explicit.
  def broadcast_change
    @registration_request.reload
    @registration_request.broadcast_refresh_later_to [ @registration_request.instance, :registration_requests ]
    @registration_request.broadcast_refresh_later
  end
end
