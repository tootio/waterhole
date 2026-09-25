# The signed-in moderator's own avatar, from our copy (see AvatarFetcher), so
# the content security policy can keep img-src to 'self'. Only ever their own:
# the header is the one place an avatar appears.
class AvatarsController < ApplicationController
  # The account menu is there before consent too. The image itself only
  # exists once they have consented (see FetchModeratorAvatarJob).
  allow_without_consent

  def show
    avatar = current_moderator.avatar
    return head :not_found unless avatar

    # The URL carries the avatar's version (see Moderator#avatar_version), so a
    # new picture is a new URL and this one may be kept.
    expires_in 1.year, public: false, immutable: true
    # Belt and braces for bytes that came from someone else's server: nothing
    # may guess another type for them, and were they ever opened as a document
    # they could run nothing and load nothing.
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "default-src 'none'; sandbox"
    send_data avatar.image, type: avatar.content_type, disposition: :inline
  end
end
