module Mastodon
  # Registers Waterhole as an OAuth app on an instance and runs the
  # authorization-code flow.
  module OAuth
    # `profile` only exists from Mastodon 4.3; older servers need read:accounts
    # just to learn who signed in. read:search lets sign-in ask the server to
    # fetch a URL, which is how it proves who it is (Instances::ProveIdentity).
    SEARCH_SCOPE  = "read:search".freeze
    MODERN_SCOPES = "profile #{SEARCH_SCOPE} admin:read:accounts admin:write:accounts".freeze
    LEGACY_SCOPES = "read:accounts #{SEARCH_SCOPE} admin:read:accounts admin:write:accounts".freeze

    module_function

    def redirect_uri = "#{Waterhole::Deployment.base_url}/oauth/callback"

    # Discovery, so we can pick scopes a given server actually understands.
    # A 404 means Mastodon < 4.3.
    def discover(instance)
      client(instance).get_public("/.well-known/oauth-authorization-server")
    rescue Mastodon::NotFound, Mastodon::Error
      {}
    end

    # LEGACY_SCOPES work on every supported Mastodon version, so anything other
    # than a positive sighting of `profile` falls back to them. Discovery 404s
    # on < 4.3, which is exactly the case that needs the fallback.
    def scopes_for(metadata)
      supported = Array(metadata["scopes_supported"])
      supported.include?("profile") ? MODERN_SCOPES : LEGACY_SCOPES
    end

    # Registering is once per instance. Re-registering when the redirect_uri
    # still matches would orphan an app and clutter the admin's app list, so
    # callers check first (see Instance#oauth_app_current?).
    def register_app(instance)
      metadata = discover(instance)
      scopes   = scopes_for(metadata)

      app = client(instance).post_public("/api/v1/apps",
        client_name: "Waterhole",
        redirect_uris: redirect_uri,
        scopes: scopes,
        website: Waterhole::Deployment.base_url)

      instance.update!(
        client_id: app["client_id"],
        client_secret: app["client_secret"],
        redirect_uri: redirect_uri,
        scopes: scopes,
        oauth_metadata: metadata
      )
      instance
    end

    def authorize_url(instance, state:)
      params = {
        client_id: instance.client_id,
        redirect_uri: instance.redirect_uri,
        response_type: "code",
        scope: instance.scopes,
        state: state
      }
      "#{instance.base_url}/oauth/authorize?#{params.to_query}"
    end

    def exchange_code(instance, code:)
      client(instance).post_public("/oauth/token",
        grant_type: "authorization_code",
        client_id: instance.client_id,
        client_secret: instance.client_secret,
        redirect_uri: instance.redirect_uri,
        scope: instance.scopes,
        code: code)
    end

    # Ends a token's authorization, which takes Waterhole off the owner's list
    # of authorized apps. Only the app that issued the token may revoke it, so
    # one issued before the app was registered again cannot be (Mastodon
    # answers 403). An unknown token counts as revoked, per RFC 7009.
    def revoke(instance, token:)
      client(instance).post_public("/oauth/revoke",
        client_id: instance.client_id,
        client_secret: instance.client_secret,
        token: token)
    end

    def client(instance) = PublicClient.new(base_url: instance.base_url)
  end
end
