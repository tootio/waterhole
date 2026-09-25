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
      WATERHOLE_SHARING_HMAC_KEY
    ].freeze

    module_function

    def host
      ENV["WATERHOLE_HOST"].presence || "localhost:3000"
    end

    def version
      if Rails.env.production?
        @version ||= detect_version
      else
        detect_version
      end
    end

    def detect_version
      ENV["WATERHOLE_VERSION"].presence || git_version
    end

    def git_version
      base = git_tag || git_branch_version || git_sha
      return "dev" unless base

      git_dirty? ? "#{base}-dev" : base
    end

    def git_tag
      %x(git describe --tags --exact-match 2>/dev/null).strip.presence
    end

    def git_branch
      %x(git branch --show-current 2>/dev/null).strip.presence
    end

    def git_branch_version
      branch = git_branch
      return unless branch

      [ branch, git_sha ].compact.join("-").presence || branch
    end

    def git_sha
      %x(git rev-parse --short HEAD 2>/dev/null).strip.presence
    end

    def git_dirty?
      %x(git status --porcelain 2>/dev/null).strip.present?
    end

    def reset_version_cache
      @version = nil
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

    # How long a decided request is kept before PurgeResolvedRequestsJob deletes it,
    # clears it. Waterhole inherits the instance's obligations over this data.
    def retention
      Integer(ENV.fetch("WATERHOLE_RETENTION_DAYS", 90)).days
    end

    # How long sync history is kept. It exists to answer "why didn't this
    # request show up?", which nobody asks of a run from last quarter -- and at
    # a sync every five minutes per instance the table gains about 105,000 rows
    # a year, none of which anything reads once they are old.
    def sync_history_retention
      Integer(ENV.fetch("WATERHOLE_SYNC_HISTORY_DAYS", 30)).days
    end

    # How long an instance keeps working after the legal documents change and
    # its DNS record goes stale. Without a window, fixing a typo in the imprint
    # would sign out every moderation team on every instance at once -- and they
    # cannot fix it themselves, they have to wait for their admin to notice.
    # Set to 0 for an immediate cut when a change really is material.
    def terms_grace_period
      Integer(ENV.fetch("WATERHOLE_TERMS_GRACE_DAYS", 14)).days
    end

    # Where operator notifications go (comma-separated for several people).
    # Nothing is sent unless this and SMTP_SERVER are both set.
    def operator_emails
      ENV["WATERHOLE_OPERATOR_EMAIL"].to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def smtp_configured? = ENV["SMTP_SERVER"].present?

    def operator_notifications? = smtp_configured? && operator_emails.any?

    def mail_from
      ENV["SMTP_FROM_ADDRESS"].presence || "Waterhole <notifications@#{host.split(":").first}>"
    end

    STARTTLS_MODES = %w[auto always never].freeze
    SMTP_AUTH_METHODS = %w[plain login cram_md5 none].freeze
    SMTP_VERIFY_MODES = %w[peer none].freeze

    # ActionMailer's smtp_settings, from the same SMTP_* variables Mastodon
    # uses, so an instance admin can copy theirs across. A value outside the
    # documented set stops the boot rather than silently sending in the clear.
    def smtp_settings
      tls = ActiveModel::Type::Boolean.new.cast(ENV["SMTP_TLS"].presence) || false
      starttls = smtp_choice("SMTP_ENABLE_STARTTLS", STARTTLS_MODES, default: "auto")
      auth = smtp_choice("SMTP_AUTH_METHOD", SMTP_AUTH_METHODS,
        default: ENV["SMTP_LOGIN"].present? ? "plain" : "none")

      {
        address: ENV.fetch("SMTP_SERVER"),
        port: Integer(ENV["SMTP_PORT"].presence || (tls ? 465 : 587)),
        domain: ENV["SMTP_DOMAIN"].presence || host.split(":").first,
        user_name: ENV["SMTP_LOGIN"].presence,
        password: ENV["SMTP_PASSWORD"].presence,
        authentication: (auth.to_sym unless auth == "none"),
        # Implicit TLS (usually port 465) and STARTTLS exclude each other.
        tls:,
        enable_starttls: !tls && starttls == "always",
        enable_starttls_auto: !tls && starttls == "auto",
        openssl_verify_mode: smtp_choice("SMTP_OPENSSL_VERIFY_MODE", SMTP_VERIFY_MODES, default: "peer"),
        ca_file: ENV["SMTP_CA_FILE"].presence,
        # A stuck mail server must not hold a job worker for minutes.
        open_timeout: 10,
        read_timeout: 10
      }.compact
    end

    def smtp_choice(name, allowed, default:)
      value = ENV[name].presence&.downcase || default
      return value if allowed.include?(value)

      raise ArgumentError, "#{name}=#{ENV[name].inspect} is not one of #{allowed.join(", ")}"
    end

    # Keys what instances compare without sharing it in the clear: the email
    # match key and the join-reason fingerprint. Changing it silently stops
    # matching what is already stored, until `waterhole:rehash_match_keys`.
    def sharing_hmac_key
      ENV["WATERHOLE_SHARING_HMAC_KEY"].presence ||
        raise("WATERHOLE_SHARING_HMAC_KEY is not set; generate one with bin/rails waterhole:secrets")
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

    # Issue forms in .github/ISSUE_TEMPLATE that issues_url can open directly.
    ISSUE_TEMPLATES = %w[bug_report watchword_suggestion].freeze

    # Where moderators can report problems or propose ideas, such as a new
    # suggested watchword. Derived from source_url when that is a GitHub
    # repository; a fork hosted elsewhere sets WATERHOLE_ISSUES_URL. Nil when
    # neither applies, and the links are left out rather than guessed.
    #
    # Only upstream is known to have our issue forms, so only there does
    # `template` open that form, with `fields` pre-filled by their ids.
    def issues_url(template: nil, **fields)
      raise ArgumentError, "unknown issue template #{template.inspect}" if template && !ISSUE_TEMPLATES.include?(template)

      url = ENV["WATERHOLE_ISSUES_URL"].to_s.strip
      return url if url.match?(%r{\Ahttps?://\S+\z}i)

      if template && source_url == DEFAULT_SOURCE_URL
        return "#{DEFAULT_SOURCE_URL}/issues/new?#{{ template: "#{template}.yml", **fields }.to_query}"
      end

      repo = source_url.match(%r{\A(https://github\.com/[^/?#]+/[^/?#]+?)(?:\.git)?/?\z}i)
      "#{repo[1]}/issues" if repo
    end

    def missing_settings
      REQUIRED_IN_PRODUCTION.select { ENV[it].blank? }
    end

    # Whether the weekly IFTAS DNI sync (SyncIftasDniBlocklistJob) is
    # scheduled at all -- see config/recurring.yml, which reads this same
    # variable to decide whether to enqueue the recurring task in the first
    # place. Running `waterhole:blocklists:sync_iftas_dni` by hand ignores
    # this: an explicit operator run always goes ahead.
    def iftas_dni_sync_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV["WATERHOLE_IFTAS_DNI_SYNC"]) || false
    end

    def iftas_dni_url
      ENV["WATERHOLE_IFTAS_DNI_URL"].presence || Blocklists::IftasDni::DEFAULT_CSV_URL
    end
  end
end
