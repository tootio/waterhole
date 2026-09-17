# Development only: signs in as a seeded moderator so the queue, flags, claims
# and notes can be exercised without a Mastodon server to OAuth against.
#
# The token is signed and expiring, and the whole controller refuses to act
# outside development, so it cannot become a back door in production.
class DevSessionsController < ApplicationController
  allow_unauthenticated_access

  before_action :ensure_development

  def create
    # The verifier serialises with JSON, so keys come back as strings.
    payload = Rails.application.message_verifier(:dev_sign_in).verified(params[:token].to_s)
    moderator = Moderator.find_by(id: payload&.dig("moderator_id"))

    if moderator.nil?
      redirect_to new_session_path, alert: "That development sign-in link is invalid or expired."
    else
      start_new_session_for(moderator)
      redirect_to root_path, notice: "Signed in as #{moderator.handle} (development)."
    end
  end

  private

  def ensure_development
    head :not_found unless Rails.env.local?
  end
end
