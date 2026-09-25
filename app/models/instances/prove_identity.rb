module Instances
  # Makes the server behind a domain prove it holds the private half of the
  # instance actor key pinned by ConfirmIdentity -- the half an impostor serving
  # the old public key does not have.
  #
  # Asked with the signing-in moderator's token to resolve a challenge URL, the
  # server fetches it signed with its instance actor's key, as it signs every
  # outgoing fetch. That fetch arrives at IdentityChallengesController, in
  # another request, which records the proof on the instance; this checks for
  # the record once the search returns.
  #
  # One proof holds for the whole instance for FRESH_FOR, so a team signing in
  # one after another costs the server one fetch, not one each.
  class ProveIdentity
    FRESH_FOR = 1.hour

    Unproven = Class.new(Mastodon::Error)

    def self.call(instance, client) = new(instance, client).call

    def initialize(instance, client)
      @instance = instance
      @client = client
    end

    def call
      # Mastodon in development does not sign its fetches, and could not reach a
      # Waterhole on localhost anyway.
      return if Rails.env.development?
      return if proven_since?(FRESH_FOR.ago)

      asked_at = Time.current
      @client.resolve(IdentityChallenge.url_for(@instance))
      return if proven_since?(asked_at)

      raise Unproven, "#{@instance.domain} could not prove it is the server that signed up here"
    end

    private

    def proven_since?(time)
      proven_at = @instance.reload.actor_key_proven_at
      proven_at.present? && proven_at >= time
    end
  end
end
