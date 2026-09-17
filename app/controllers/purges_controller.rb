# A moderator purging one request on demand: what PurgeResolvedRequestsJob
# does once the retention period has passed, now. The request is deleted with
# everything attached, and sync never imports it again.
class PurgesController < ApplicationController
  def create
    request = registration_requests_scope.find(params[:registration_request_id])
    request.purge!

    redirect_to root_path, notice: "Purged @#{request.username} and everything about it from this Waterhole."
  end
end
