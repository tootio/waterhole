# Copies a moderator's avatar to our own origin; see AvatarFetcher. Anything
# it refuses leaves no avatar, and the header shows an initial instead. Only
# for moderators who have consented: the consent page is where they agree to
# us keeping their avatar.
class FetchModeratorAvatarJob < ApplicationJob
  queue_as :default

  def perform(moderator)
    url = moderator.avatar_url
    return moderator.avatar&.destroy! if url.blank? || !moderator.consent_current?

    image, content_type = AvatarFetcher.fetch(url)
    avatar = moderator.avatar || moderator.build_avatar
    avatar.update!(image:, content_type:, source_url: url)
  rescue AvatarFetcher::Rejected => e
    Rails.logger.warn("[waterhole] no avatar for #{moderator.handle}: #{e.message}")
    # A copy of this same URL is still the right picture; one of an old URL is not.
    moderator.avatar&.destroy! unless moderator.stored_avatar_url == url
  end
end
