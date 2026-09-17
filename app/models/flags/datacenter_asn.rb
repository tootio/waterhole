module Flags
  # Ordinary applicants do not sign up from an AWS address. A signup originating
  # from a hosting or VPN network is one of the stronger spam signals available.
  #
  # Never more than `warning`, and always names the ASN and organisation, because
  # a meaningful share of privacy-conscious Mastodon applicants legitimately sign
  # up over a VPN. A moderator has to be able to judge the evidence rather than
  # trust the list.
  class DatacenterAsn < Rule
    ASN_PATH     = Rails.root.join("lib/data/datacenter_asns.txt")
    KEYWORD_PATH = Rails.root.join("lib/data/datacenter_asn_keywords.txt")

    class << self
      def asns = @asns ||= load(ASN_PATH) { it.split("#").first.to_s.strip.to_i }.to_set

      def keywords = @keywords ||= load(KEYWORD_PATH, &:downcase)

      private

      def load(path)
        path.readlines(chomp: true).filter_map do |line|
          next if line.strip.start_with?("#") || line.strip.empty?

          value = yield(line.strip)
          value unless value == 0 || value.to_s.empty?
        end
      end
    end

    def call
      return nil if request.ip_asn.blank? && request.ip_asn_org.blank?
      # iCloud Private Relay leaves through Cloudflare, Akamai and Fastly: a
      # datacenter address, but an ordinary Safari user behind it.
      return nil if request.ip_relay_private_relay?

      if self.class.asns.include?(request.ip_asn)
        detect(:warning, **details(matched: "asn"))
      elsif (keyword = matching_keyword)
        # A name match is a heuristic, so it must not look as serious as a known
        # network.
        detect(:info, **details(matched: "keyword", pattern: keyword))
      end
    end

    private

    def matching_keyword
      org = request.ip_asn_org.to_s.downcase
      return nil if org.blank?

      self.class.keywords.find { org.include?(it) }
    end

    # data_age_days travels with the flag on purpose: staleness matters at the
    # moment a moderator decides whether to trust it, not on a status page.
    def details(**extra)
      { asn: request.ip_asn, org: request.ip_asn_org,
        data_age_days: Ip::Databases.age_in_days(Ip::Databases::ASN) }.compact.merge(extra)
    end
  end
end
