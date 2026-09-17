class ApplicationController < ActionController::Base
  include Authentication
  include RecentInstances

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Solid Cache in production, so every Puma worker counts against the same
  # limit. See config/environments/test.rb for the exception.
  RATE_LIMIT_STORE = Rails.configuration.x.rate_limit_store || Rails.cache

  # Throttles by client IP unless told otherwise.
  def self.throttle(to:, within:, name:, **options)
    rate_limit(to:, within:, name:, store: RATE_LIMIT_STORE, with: -> { rate_limited(within) }, **options)
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
