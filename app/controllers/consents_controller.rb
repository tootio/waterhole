# A moderator's explicit consent to the processing of their data, asked right
# after signing in and again whenever the privacy policy changes. Until they
# agree, the rest of Waterhole redirects here (Authentication#require_consent).
class ConsentsController < ApplicationController
  allow_without_consent

  def show; end

  def create
    current_moderator.consent!
    redirect_to after_authentication_url, notice: "Thanks. Welcome to the waterhole."
  end

  # Declining signs the moderator out and keeps nothing about them.
  def destroy
    moderator = current_moderator
    terminate_session
    moderator.forget!
    redirect_to new_session_path, notice: "You declined, so you are signed out and we have deleted your data."
  end
end
