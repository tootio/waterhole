module Mastodon
  # One page of a paginated admin listing, plus the cursor for the next.
  Page = Data.define(:records, :next_max_id) do
    def more? = next_max_id.present?

    # Mastodon paginates with an RFC 5988 Link header:
    #   <https://host/api/v2/admin/accounts?max_id=123>; rel="next", <...>; rel="prev"
    def self.from(records, link_header)
      Page.new(records:, next_max_id: parse_next_max_id(link_header))
    end

    def self.parse_next_max_id(link_header)
      return nil if link_header.blank?

      link_header.split(",").each do |part|
        url, *params = part.split(";").map(&:strip)
        next unless params.any? { |p| p.match?(/rel\s*=\s*"?next"?/) }

        uri = URI.parse(url.delete_prefix("<").delete_suffix(">")) rescue next
        return Rack::Utils.parse_query(uri.query)["max_id"].presence
      end
      nil
    end
  end
end
