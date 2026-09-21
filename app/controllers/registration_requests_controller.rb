class RegistrationRequestsController < ApplicationController
  include RegistrationRequestFilters

  before_action :set_registration_request, only: %i[show next previous]

  helper_method :queue_page_path

  def index
    @query = RegistrationRequests::Query.new(registration_requests_scope, filter_params, viewer: current_moderator)
    @pagination = Pagination.new(@query.call, page: params[:page])
    @registration_requests = @pagination.records
    pending  = registration_requests_scope.pending
    awaiting = pending.email_confirmed
    @counts = {
      pending: awaiting.count,
      unclaimed: awaiting.unclaimed.count,
      # a moderator can claim unconfirmed registrations. Count them, too.
      mine: pending.claimed_by_moderator(current_moderator).count,
      # Hidden by default, so say how many there are rather than let them vanish.
      unconfirmed: pending.email_unconfirmed.count
    }
  end

  def show
    @notes = @registration_request.notes.roots.includes(:moderator, replies: :moderator).chronological
    @note  = @registration_request.notes.new
    # Rebuilt from the permitted filters the row link handed back to us, never
    # from a raw url, so this can't be turned into an open redirect.
    @back_to_queue_path = registration_requests_path(filter_params)
    @show_list_nav = RegistrationRequests::Neighbors.new(filtered_registration_requests, @registration_request).in_list?
  end

  def next     = redirect_to_neighbor(:after)
  def previous = redirect_to_neighbor(:before)

  private

  def redirect_to_neighbor(direction)
    target = RegistrationRequests::Neighbors.new(filtered_registration_requests, @registration_request).public_send(direction)

    if target
      redirect_to registration_request_path(target, filter_params)
    else
      redirect_to registration_requests_path(filter_params),
        notice: "No more requests in this list — back to the queue."
    end
  end

  def set_registration_request
    @registration_request = registration_requests_scope
      .includes(:flags, :claimed_by, :decision).find(params[:id])
  end

  # Built from the permitted filters only. Handing url_for the raw query string
  # let ?host= and ?protocol= rewrite the link into another origin or a
  # javascript: URL.
  def queue_page_path(page) = registration_requests_path(filter_params.merge(page:))
end
