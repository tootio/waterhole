# Where a Mastodon server answers the challenge Instances::ProveIdentity sets:
# the server fetches this URL signed with its instance actor's key, and a
# signature made with the pinned key is the proof.
class IdentityChallengesController < ApplicationController
  allow_unauthenticated_access
  allow_without_consent

  # Each attempt means a signature check, and there is no reason for more than
  # a sign-in's worth of them.
  throttle to: 20, within: 3.minutes, name: "identity_challenge"

  def show
    instance = Instances::IdentityChallenge.instance_for(params[:token])

    if instance && HttpSignature.verified?(request, instance.actor_public_key)
      instance.update!(actor_key_proven_at: Time.current)
      head :no_content
    else
      # Not 401: that makes Mastodon knock again with RFC 9421 signatures,
      # which HttpSignature does not read.
      head :forbidden
    end
  end
end
