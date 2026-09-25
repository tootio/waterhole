# Is this moderator still allowed to work the queue? See VerifyModeratorsJob.
class VerifyModeratorJob < ApplicationJob
  queue_as :default

  def perform(moderator)
    return unless moderator.token_usable?

    client = Mastodon::Client.new(base_url: moderator.instance.base_url, access_token: moderator.access_token)
    account = client.verify_credentials

    if Mastodon::Role.can_manage_users?(account, client)
      moderator.update!(role_name: account.dig("role", "name"),
        avatar_url: Moderator.avatar_url_from(account))
      moderator.refresh_avatar_later
    else
      moderator.invalidate_token!
    end
  rescue Mastodon::Unauthorized
    moderator.invalidate_token!
  rescue Mastodon::ConnectionError, Mastodon::ServerError, Mastodon::RateLimited => e
    # An outage says nothing about the role. Locking a whole team out over it
    # would be worse than waiting for the next hourly check, and a session ends
    # within Session::ABSOLUTE_LIFETIME regardless.
    Rails.logger.warn("[waterhole] could not re-check #{moderator.handle}: #{e.message}")
  end
end
