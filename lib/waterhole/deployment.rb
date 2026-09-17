# Deployment-level settings for this Waterhole install.
#
# Every Waterhole runs the same code, and a Mastodon instance picks which one to
# authorise, so everything that makes one deployment differ from another is
# read from ENV here -- never from Rails credentials or config/environments.
# .env.production.sample documents each variable.
#
# `host` is what instance admins put in their DNS TXT record, so it must be the
# canonical public host of this deployment and must stay stable -- changing it
# invalidates every instance's published record at once.
module Waterhole
  module Deployment
    POLICY_MODES = %w[allow_all allowlist_only].freeze

    # Without these a production boot is refused rather than half-working; see
    # config/initializers/waterhole.rb.
    REQUIRED_IN_PRODUCTION = %w[
      WATERHOLE_HOST
      SECRET_KEY_BASE
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
      WATERHOLE_EMAIL_HMAC_KEY
    ].freeze

    module_function

    def host
      ENV["WATERHOLE_HOST"].presence || "localhost:3000"
    end

    def base_url
      scheme = Rails.env.local? ? "http" : "https"
      "#{scheme}://#{host}"
    end

    def policy_mode
      mode = ENV["WATERHOLE_POLICY_MODE"].presence || "allow_all"
      POLICY_MODES.include?(mode) ? mode : "allow_all"
    end

    def allowlist_only? = policy_mode == "allowlist_only"

    # How long a decided request keeps its personal data before the purge job
    # clears it. Waterhole inherits the instance's obligations over this data.
    def pii_retention
      Integer(ENV.fetch("WATERHOLE_PII_RETENTION_DAYS", 90)).days
    end

    # How long an instance keeps working after the legal documents change and
    # its DNS record goes stale. Without a window, fixing a typo in the imprint
    # would sign out every moderation team on every instance at once -- and they
    # cannot fix it themselves, they have to wait for their admin to notice.
    # Set to 0 for an immediate cut when a change really is material.
    def terms_grace_period
      Integer(ENV.fetch("WATERHOLE_TERMS_GRACE_DAYS", 14)).days
    end

    # Keys the cross-instance email match. Changing it silently stops matching
    # every address already stored, until each request is next synced.
    def canonical_email_hmac_key
      ENV["WATERHOLE_EMAIL_HMAC_KEY"].presence ||
        raise("WATERHOLE_EMAIL_HMAC_KEY is not set; generate one with bin/rails waterhole:secrets")
    end

    # Where the operator's terms, privacy policy and imprint live. Not
    # config/legal: that holds the templates shipped with the code. The default
    # is on the storage volume, so the documents survive an image upgrade.
    def legal_directory
      Pathname(ENV["WATERHOLE_LEGAL_DIR"].presence || Rails.root.join("storage/legal"))
    end

    DEFAULT_SOURCE_URL = "https://github.com/tootio/waterhole"

    # Where this deployment's source code can be downloaded, linked from the
    # footer. Waterhole is AGPL-3.0: whoever runs a *modified* version must
    # offer its users that modified source (section 13) by pointing this at it.
    # Anything other than an http(s) URL falls back to upstream, so a typo can
    # neither become a javascript: link nor remove the link altogether.
    def source_url
      url = ENV["WATERHOLE_SOURCE_URL"].to_s.strip
      url.match?(%r{\Ahttps?://\S+\z}i) ? url : DEFAULT_SOURCE_URL
    end

    def missing_settings
      REQUIRED_IN_PRODUCTION.select { ENV[it].blank? }
    end
  end
end
