module Flags
  # The address is at a throwaway provider (DomainLists::DisposableEmailDomains), or a
  # subdomain of one.
  class DisposableEmail < Rule
    # What the flag says for an address at `domain`, or nil for no flag.
    # RefreshDisposableEmailDomainsJob compares these with the stored flags.
    def self.details_for(domain)
      listed = DomainLists::DisposableEmailDomains.listed_domain(domain)
      { domain:, listed: (listed unless listed == domain) }.compact if listed
    end

    def call
      details = self.class.details_for(request.email_domain)
      detect(:warning, **details) if details
    end
  end
end
