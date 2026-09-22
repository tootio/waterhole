require "simpleidn"

# Reduces an address to the mailbox behind it, so that sub-address tags, ignored
# dots and a provider's alias domains don't let the same person look like
# different applicants across instances.
#
# For matching, not for sending: the result is not necessarily an address that
# delivers. Changing the rules changes every stored canonical_email_hash, so
# after an edit here run `bin/rails waterhole:rehash_match_keys`.
module EmailCanonicalizer
  # How a mailbox provider treats the local part.
  #   canonical_domain  replaces the domain where several share one namespace
  #   tag_separators    everything from the first of these on is a tag
  #   ignored_chars     removed from the local part
  #   replacements      applied after that, for characters that mean the same
  Provider = Data.define(:canonical_domain, :tag_separators, :ignored_chars, :replacements) do
    def initialize(canonical_domain: nil, tag_separators: "+", ignored_chars: "", replacements: {})
      super
    end
  end

  DEFAULT = Provider.new

  GMAIL = Provider.new(canonical_domain: "gmail.com", ignored_chars: ".")
  # Proton ignores dots, hyphens and underscores in usernames, and all its
  # domains share one namespace.
  PROTON = Provider.new(canonical_domain: "proton.me", ignored_chars: ".-_")
  # iCloud, me.com and mac.com addresses of the same name are one account.
  APPLE = Provider.new(canonical_domain: "icloud.com")
  # Yahoo usernames cannot contain hyphens; disposable addresses are
  # "name-keyword". Its domains are separate namespaces.
  YAHOO = Provider.new(tag_separators: "+-")
  # Yandex treats dots and hyphens in logins as the same character, and all its
  # domains share one namespace.
  YANDEX = Provider.new(canonical_domain: "yandex.ru", replacements: { "." => "-" })

  PROVIDERS = {
    "gmail.com" => GMAIL, "googlemail.com" => GMAIL,
    "proton.me" => PROTON, "protonmail.com" => PROTON, "protonmail.ch" => PROTON, "pm.me" => PROTON,
    "icloud.com" => APPLE, "me.com" => APPLE, "mac.com" => APPLE,
    "yahoo.com" => YAHOO, "yahoo.co.uk" => YAHOO, "yahoo.de" => YAHOO, "yahoo.fr" => YAHOO,
    "yahoo.es" => YAHOO, "yahoo.it" => YAHOO, "yahoo.ca" => YAHOO, "yahoo.com.au" => YAHOO,
    "yahoo.com.br" => YAHOO, "yahoo.co.in" => YAHOO, "ymail.com" => YAHOO, "rocketmail.com" => YAHOO,
    "yandex.ru" => YANDEX, "yandex.com" => YANDEX, "yandex.by" => YANDEX, "yandex.kz" => YANDEX,
    "yandex.ua" => YANDEX, "yandex.com.tr" => YANDEX, "ya.ru" => YANDEX
  }.freeze

  # Subdomain addressing: anything@user.fastmail.com reaches user@fastmail.com.
  FASTMAIL_DOMAINS = %w[fastmail.com fastmail.fm].freeze

  module_function

  # nil for anything that is not local@domain, so junk never becomes a match key.
  def canonicalize(email)
    local, domain = split(email)
    return nil if local.nil?

    # Quoted local parts are taken literally.
    return "#{local}@#{domain}" if local.start_with?('"')

    FASTMAIL_DOMAINS.each do |fastmail|
      sub = domain.delete_suffix(".#{fastmail}")
      next if sub == domain || sub.empty? || sub.include?(".")

      local, domain = sub, fastmail
      break
    end

    provider = PROVIDERS.fetch(domain, DEFAULT)
    canonical = local
    tag_at = canonical.index(/[#{Regexp.escape(provider.tag_separators)}]/)
    canonical = canonical[0...tag_at] if tag_at
    canonical = canonical.gsub(/[#{Regexp.escape(provider.ignored_chars)}]/, "") unless provider.ignored_chars.empty?
    provider.replacements.each { |from, to| canonical = canonical.gsub(from, to) }
    # Never collapse to an empty local part, e.g. "+tag@example.com".
    canonical = local if canonical.empty?

    "#{canonical}@#{provider.canonical_domain || domain}"
  end

  # The domain as written, normalised (lowercase, punycode, no trailing dot)
  # but not merged with its provider's aliases: the disposable-domain flag and
  # the queue filter need the real one.
  def domain_of(email) = split(email)&.last

  # resolves a normalised domain to its canonical domain
  def resolve_canonical_domain(domain)
    PROVIDERS[domain]&.canonical_domain.presence || domain
  end

  # HMAC rather than a bare digest: the space of email addresses is small enough
  # to enumerate against an unsalted hash, so a leaked index would be reversible.
  def hash_for(email)
    canonical = canonicalize(email)
    return nil if canonical.blank?

    OpenSSL::HMAC.hexdigest("SHA256", Waterhole::Deployment.sharing_hmac_key, canonical)
  end

  # [local, domain] with the local part lowercased, or nil. Splits at the last
  # "@", which a quoted local part may itself contain.
  def split(email)
    address = email.to_s.strip.delete_prefix("<").delete_suffix(">")
    at = address.rindex("@") or return nil

    local = address[0...at].downcase
    domain = normalise_domain(address[(at + 1)..])
    return nil if local.empty? || domain.empty?

    [ local, domain ]
  end

  def normalise_domain(domain)
    domain = domain.delete_suffix(".")
    SimpleIDN.to_ascii(domain).downcase
  rescue StandardError
    domain.downcase
  end
end
