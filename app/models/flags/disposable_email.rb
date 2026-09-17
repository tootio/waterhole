module Flags
  class DisposableEmail < Rule
    PATH = Rails.root.join("lib/data/disposable_email_domains.txt")

    def self.domains
      @domains ||= PATH.readlines(chomp: true)
        .filter_map { |line| line.strip.downcase.presence unless line.start_with?("#") }
        .to_set
    end

    def call
      domain = request.email_domain.presence&.downcase
      return nil if domain.blank? || self.class.domains.exclude?(domain)

      detect(:warning, domain:)
    end
  end
end
