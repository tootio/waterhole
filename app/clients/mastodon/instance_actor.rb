module Mastodon
  # The actor a Mastodon server federates as itself, at /actor.
  #
  # Its keypair is generated when the server's database is first set up and
  # lives in that database, so it stays through a move to new hardware but not
  # through a fresh install. That makes it the closest thing Mastodon has to an
  # instance id: the API itself names a server only by its domain.
  module InstanceActor
    PATH = "/actor".freeze

    module_function

    # Normalised PEM, so formatting differences never read as a different key.
    def public_key(instance)
      document = PublicClient.new(base_url: instance.base_url).get_activity(PATH)
      pem = document.dig("publicKey", "publicKeyPem") if document.is_a?(Hash)
      raise InvalidResponse, "#{PATH} has no public key" unless pem.is_a?(String)

      OpenSSL::PKey.read(pem).public_to_pem
    rescue OpenSSL::PKey::PKeyError
      raise InvalidResponse, "#{PATH} has an unreadable public key"
    end
  end
end
