# The current moderator's vote on a request: cast, change or withdraw. Like
# claiming it must hold up to double clicks, so it is an upsert on the unique
# index rather than read-then-write.
class VotesController < ApplicationController
  throttle to: 30, within: 1.minute, name: "vote", by: -> { current_moderator.id }

  before_action :set_registration_request
  before_action :require_open

  def update
    vote = params.expect(:vote)
    unless Vote::VOTES.include?(vote)
      return redirect_to registration_request_path(@registration_request), alert: "Unknown vote."
    end

    # upsert fills in the timestamps itself, and bumps updated_at only on a change.
    Vote.upsert({ registration_request_id: @registration_request.id, moderator_id: current_moderator.id, vote: },
      unique_by: %i[registration_request_id moderator_id], update_only: :vote)
    broadcast_change
    redirect_to registration_request_path(@registration_request)
  end

  def destroy
    @registration_request.votes.where(moderator: current_moderator).delete_all
    broadcast_change
    redirect_to registration_request_path(@registration_request)
  end

  private

  def set_registration_request
    @registration_request = registration_requests_scope.find(params[:registration_request_id])
  end

  # A vote advises the decision; once there is one, it has nothing left to say.
  def require_open
    return unless @registration_request.resolved?

    redirect_to registration_request_path(@registration_request), alert: "Voting is closed once a request is decided."
  end

  # upsert and delete_all skip callbacks, so the broadcast is explicit. A refresh,
  # not a targeted replace: the tally shows each viewer their own vote.
  def broadcast_change
    @registration_request.broadcast_refresh_later
  end
end
