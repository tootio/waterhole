module Mastodon
  # Unauthenticated calls: app registration, scope discovery and token exchange.
  class PublicClient < Client
    def initialize(base_url:) = super(base_url:, access_token: nil)

    def get_public(path, **params) = send(:raw_get, path, **params).body
    def post_public(path, **params) = send(:post, path, **params)
  end
end
