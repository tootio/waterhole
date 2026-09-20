class ApplicationController < ActionController::Base
  include Authentication
  include RecentInstances

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Throttles by client IP unless told otherwise.
  def self.throttle(to:, within:, name:, **options)
    rate_limit(to:, within:, name:, with: -> { rate_limited(within) }, **options)
  end

  private

  def rate_limited(within)
    response.set_header("Retry-After", within.to_i.to_s)
    render "shared/rate_limited", status: :too_many_requests
  end

  # Tenancy is enforced by scoping through the association rather than by a
  # check that can be forgotten: a moderator on one instance simply cannot
  # address another instance's records.
  def registration_requests_scope
    current_instance.registration_requests
  end
end
