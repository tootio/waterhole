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

  # Declining signs the moderator out and keeps nothing about them, and asks
  # Mastodon to end the authorization too. That last part is best effort: the
  # data here is gone either way, and the notice says what is left to do.
  def destroy
    moderator = current_moderator
    instance = moderator.instance
    token = moderator.access_token if moderator.token_usable?
    terminate_session
    moderator.forget!

    redirect_to new_session_path, notice: declined_notice(instance, revoked: token.present? && revoke(instance, token))
  end

  private

  def revoke(instance, token)
    Mastodon::OAuth.revoke(instance, token:)
    true
  rescue Mastodon::Error => e
    Rails.logger.info("[waterhole] could not revoke a declining moderator's token on #{instance.domain}: #{e.message}")
    false
  end

  # Even after a revoke, Mastodon may list an authorization from before the app
  # was registered again, which only the moderator can remove.
  def declined_notice(instance, revoked:)
    text = "You declined, so you are signed out and we have deleted your data."
    text += if revoked
      " Waterhole's access to your account on #{instance.domain} is revoked, too. " \
        "If Mastodon still lists Waterhole among your authorized apps, that is an older authorization you can revoke there."
    else
      " Mastodon still lists Waterhole among your authorized apps until you revoke it there."
    end

    { "text" => text, "link_text" => "Open your authorized apps", "link_url" => instance.authorized_apps_url }
  end
end
