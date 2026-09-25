module Instances
  # Makes sure the Mastodon install behind a domain is the one Waterhole knows.
  #
  # A domain can change hands: the instance that signed up lets it lapse, and a
  # new install comes up under the same name. Without this, the new install's
  # staff would sign in to the old team's queue, notes and history.
  #
  # The first sign-in pins the instance actor's public key; every later one
  # compares. A different key means a different install, so the record starts
  # over (Instance#start_over!). A key that cannot be read stops the sign-in
  # rather than being taken on trust.
  #
  # This alone catches a fresh install, not an impostor: the key is public, and
  # whoever holds the domain could serve the old one. ProveIdentity, later in
  # the same sign-in, checks the server holds the private half.
  class ConfirmIdentity
    def self.call(instance) = new(instance).call

    def initialize(instance)
      @instance = instance
    end

    def call
      key = Mastodon::InstanceActor.public_key(@instance)

      if @instance.actor_public_key.blank?
        @instance.update!(actor_public_key: key, actor_key_pinned_at: Time.current)
      elsif @instance.actor_public_key != key
        Rails.logger.warn("[waterhole] #{@instance.domain} answers with a different instance actor key; starting over")
        @instance.start_over!(actor_public_key: key)
      end

      @instance
    end
  end
end
