# Reduces an address to the identity behind it, so that plus-extensions and
# Gmail's ignored dots don't let the same person look like different applicants
# across instances.
module EmailCanonicalizer
  # Providers that ignore dots in the local part.
  DOT_INSENSITIVE_DOMAINS = %w[
    gmail.com googlemail.com
  ].freeze

  module_function

  def canonicalize(email)
    local, domain = email.to_s.strip.downcase.split("@", 2)
    return nil if local.blank? || domain.blank?

    local = local.split("+", 2).first.to_s
    local = local.delete(".") if DOT_INSENSITIVE_DOMAINS.include?(domain)
    return nil if local.blank?

    "#{local}@#{domain}"
  end

  def domain_of(email) = email.to_s.strip.downcase.split("@", 2).last.presence

  # HMAC rather than a bare digest: the space of email addresses is small enough
  # to enumerate against an unsalted hash, so a leaked index would be reversible.
  def hash_for(email)
    canonical = canonicalize(email)
    return nil if canonical.blank?

    OpenSSL::HMAC.hexdigest("SHA256", Waterhole::Deployment.canonical_email_hmac_key, canonical)
  end
end
