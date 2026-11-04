module MailInfrastructure
  # The MX hosts of an email domain, best preference first, and the addresses they
  # point to. Raises one of DnsAllowlist::Resolver::ERRORS when DNS gave no usable
  # answer: that says nothing about the domain, so it must not be stored or cached as
  # an answer. That goes for the addresses too when no host answered, or an outage
  # between the two steps would lose them for good. One host failing is not an outage:
  # a stale backup MX must not cost a domain the evidence in its other hosts.
  module Lookup
    # Long enough that a burst of signups from one domain asks once, short enough
    # that what gets stored still describes the moment of the signup.
    CACHE_TTL = 15.minutes

    # Sync asks on every pass while there is no answer. A domain that doesn't answer
    # is the applicant's to choose, and each try holds a worker for seconds.
    FAILURE_BACKOFF = 30.minutes

    # The domain, and so its answer, is the applicant's to choose. Real domains
    # have a handful.
    MAX_HOSTS = 10
    MAX_RESOLVED_HOSTS = 3
    MAX_ADDRESSES = 16

    NOTHING = { hosts: [], addresses: [] }.freeze

    HOSTNAME = /\A(?=.{1,253}\z)[a-z0-9-]{1,63}(\.[a-z0-9-]{1,63})+\z/

    class << self
      attr_writer :resolver

      def resolver = @resolver || DnsAllowlist::Resolver.new

      # Test seam, shaped like DnsAllowlist.stub_resolver.
      def stub_resolver(resolver)
        previous = @resolver
        @resolver = resolver
        yield
      ensure
        @resolver = previous
      end

      def call(domain)
        return NOTHING unless HOSTNAME.match?(domain.to_s)

        Rails.cache.fetch(answer_key(domain), expires_in: CACHE_TTL) do
          hosts = normalise(resolver.mx_records("#{domain}."))
          { hosts:, addresses: addresses_of(hosts) }
        end
      rescue *DnsAllowlist::Resolver::ERRORS
        Rails.cache.write(failure_key(domain), true, expires_in: FAILURE_BACKOFF)
        raise
      end

      def recently_failed?(domain) = Rails.cache.exist?(failure_key(domain))

      # The keys name the domain, and an entry's row outlives its expiry until the
      # store evicts it. Deleting a request must not leave that behind.
      def forget(domain)
        Rails.cache.delete(answer_key(domain))
        Rails.cache.delete(failure_key(domain))
      end

      private

      def answer_key(domain) = "mail_infrastructure/mx/#{domain}"

      def failure_key(domain) = "mail_infrastructure/mx-failed/#{domain}"

      # Private and reserved addresses go: a domain's MX can point anywhere, and those
      # say nothing about who receives its mail.
      #
      # Cut to size before sorting, so that the best hosts' addresses are the ones kept.
      def addresses_of(hosts)
        answers = hosts.first(MAX_RESOLVED_HOSTS).map do |host|
          resolver.address_records("#{host}.")
        rescue *DnsAllowlist::Resolver::ERRORS => e
          e
        end
        failures, addresses = answers.partition { it.is_a?(Exception) }
        raise failures.first if addresses.empty? && failures.any?

        addresses.flatten
          .map { IPAddr.new(it) }
          .select { SsrfGuard.allowed?(it) }
          .map(&:to_s)
          .uniq
          .first(MAX_ADDRESSES)
          .sort
      end

      # A null MX (RFC 7505) has an empty host, which is no hostname and goes.
      def normalise(records)
        records
          .map { |preference, host| [ preference, host.downcase ] }
          .select { |_, host| HOSTNAME.match?(host) }
          .sort
          .map(&:last)
          .uniq
          .first(MAX_HOSTS)
      end
    end
  end
end
