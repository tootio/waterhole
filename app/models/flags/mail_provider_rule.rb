module Flags
  # One rule per MailInfrastructure provider, generated so that no second list of
  # them exists: each gets its own label, help page, filter entry and `flag:` search term.
  #
  # Reads the MX hosts and addresses stored on the request, so this stays a pure
  # function of the database (see RegistrationRequests::Enrichment on why that
  # matters). The lookup itself is LookupMailInfrastructureJob's.
  class MailProviderRule < Rule
    class << self
      attr_reader :provider

      def rules = @rules ||= MailInfrastructure::PROVIDERS.map { generate(it) }

      def rule_names = rules.map(&:rule_name)

      private

      # A named constant, so that Rule.rule_name works as it does everywhere else.
      def generate(provider)
        const_set(provider.key.camelize, Class.new(self) { @provider = provider })
      end
    end

    def call
      provider = self.class.provider
      domain, hosts, addresses = request.email_domain.to_s, Array(request.email_mx_hosts), Array(request.email_mx_addresses)

      # Nearly every rule stops here. Only a match needs the whole classification, to
      # see whether another provider subsumes it.
      return unless provider.match_for(domain, hosts, addresses)
      return if provider.unless_on_blocklist && Flags::DisposableEmail.details_for(domain)

      match = MailInfrastructure.classify(domain:, hosts:, addresses:).find { it.provider == provider }

      detect(provider.severity, domain:, matched: match.matched, via: match.via) if match
    end
  end
end
