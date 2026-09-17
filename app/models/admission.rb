# Decides whether a domain may connect to this Waterhole at all.
#
# Two gates, evaluated cheapest-first so that a blocked domain never causes a DNS
# lookup or an outbound HTTP request to a server we have no business contacting:
#
#   1. DomainPolicy -- the operator's allow/blocklist for this deployment.
#   2. DnsAllowlist -- the instance admin's TXT record opt-in.
#
# The third gate, "may this person act?", is Mastodon's own role check and
# happens later, at the API call.
class Admission
  Result = Data.define(:outcome, :message, :dns, :warning) do
    def admitted? = outcome == :admitted

    # A policy refusal is final; a DNS refusal is fixable by publishing a record.
    def fixable_by_admin?
      %i[dns_not_allowlisted dns_ambiguous dns_unreachable terms_outdated].include?(outcome)
    end

    def policy_refusal? = %i[blocked_by_policy not_on_allowlist].include?(outcome)

    def terms_problem? = outcome == :terms_outdated || warning.present?

    # Whether the record we suggest should start out with signals=on: yes
    # wherever the admin has opted in, so republishing -- to accept new terms,
    # or to settle conflicting records -- never quietly opts an instance out.
    # With conflicting records, which one says what is chance; the opt-in we
    # last recorded is not.
    def suggest_signals?(domain)
      return Instance.find_by(domain:)&.signals_opted_in? || false if dns&.ambiguous?

      dns&.signals.present?
    end
  end

  def self.call(domain, resolver: nil) = new(domain, resolver:).call

  def initialize(domain, resolver: nil)
    @domain   = domain.to_s.strip.downcase
    @resolver = resolver
  end

  def call
    refusal = policy_refusal
    return refusal if refusal

    dns = DnsAllowlist.call(@domain, resolver: @resolver)

    case dns.outcome
    when :verified
      Result.new(outcome: :admitted, message: nil, dns:, warning: nil)
    when :terms_outdated
      terms_refusal(dns)
    when :ambiguous
      Result.new(outcome: :dns_ambiguous, warning: nil, dns:,
        message: "#{@domain} publishes more than one different DNS record for " \
                 "#{Waterhole::Deployment.host}. Keep exactly one: with several, the answer " \
                 "would depend on which one DNS happens to return first.")
    when :not_allowlisted
      Result.new(outcome: :dns_not_allowlisted, warning: nil,
        message: "#{@domain} has not published a DNS record authorising #{Waterhole::Deployment.host}.", dns:)
    else
      Result.new(outcome: :dns_unreachable, warning: nil,
        message: "Could not reach DNS for #{@domain}. This is a problem on our side; try again shortly.", dns:)
    end
  end

  private

  # A record is published for us, but it accepts a different version of the legal
  # documents. An instance that already accepted an earlier version keeps working
  # until its grace window closes, so that editing a typo does not sign out every
  # moderation team at once.
  def terms_refusal(dns)
    instance = Instance.find_by(domain: @domain)

    if instance&.terms_grace_active?
      Result.new(outcome: :admitted, message: nil, dns:,
        warning: "#{@domain} needs to republish its DNS record to accept the updated terms " \
                 "by #{I18n.l(instance.terms_grace_until, format: :long)}.")
    else
      Result.new(outcome: :terms_outdated, dns:, warning: nil,
        message: "#{@domain} has not accepted the current terms of this Waterhole. " \
                 "Its DNS record needs republishing with the current accepted= value.")
    end
  end

  # Deny always wins: a blocklist an allowlist entry could override is not a
  # blocklist.
  def policy_refusal
    policies = DomainPolicy.matching(@domain).to_a

    if (blocked = policies.find(&:blocked?))
      return Result.new(outcome: :blocked_by_policy, dns: nil, warning: nil,
        message: blocked.reason.presence || "#{@domain} is not served by this Waterhole.")
    end

    if Waterhole::Deployment.allowlist_only? && policies.none?(&:allowed?)
      return Result.new(outcome: :not_on_allowlist, dns: nil, warning: nil,
        message: "This Waterhole only serves specific instances, and #{@domain} is not one of them.")
    end

    nil
  end
end
