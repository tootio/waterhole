module Mastodon
  # Unauthenticated calls: app registration, scope discovery, token exchange and
  # the instance actor.
  class PublicClient < Client
    def initialize(base_url:) = super(base_url:, access_token: nil)

    def get_public(path, **params) = send(:raw_get, path, **params).body
    def post_public(path, **params) = send(:post, path, **params)

    # ActivityPub documents are only served to a client that asks for them.
    def get_activity(path)
      request { connection.get(path, nil, "Accept" => "application/activity+json") }.body
    end
  end
end
