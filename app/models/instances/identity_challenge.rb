module Instances
  # The URL a server is asked to fetch to prove it holds its instance actor's
  # private key: signed by us, short-lived, and bound to the key it must be
  # answered with, so a key replaced in the meantime cannot answer it.
  #
  # URL-safe, because it travels in the path, and Mastodon signs the path exactly
  # as it normalised it.
  module IdentityChallenge
    TTL = 5.minutes

    module_function

    def url_for(instance)
      token = verifier.generate({ instance_id: instance.id, key: fingerprint(instance.actor_public_key) },
        expires_in: TTL, purpose: :identity_challenge)
      "#{Waterhole::Deployment.base_url}/identity_challenges/#{token}"
    end

    # The instance the token was issued for, while its key is still the same.
    def instance_for(token)
      payload = verifier.verified(token.to_s, purpose: :identity_challenge)
      return if payload.blank?

      instance = Instance.find_by(id: payload["instance_id"])
      instance if instance&.actor_public_key.present? &&
        ActiveSupport::SecurityUtils.secure_compare(fingerprint(instance.actor_public_key), payload["key"].to_s)
    end

    def fingerprint(pem) = Digest::SHA256.hexdigest(pem.to_s)

    def verifier
      @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key("identity_challenge"), url_safe: true, serializer: JSON
      )
    end
  end
end
