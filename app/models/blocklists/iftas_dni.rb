require "csv"

module Blocklists
  # IFTAS's shared "Do Not Interact" list: domains associated with abuse
  # (CSAM, hate speech, harassment, etc.), published as a Mastodon-shaped
  # domain-block CSV export
  # (#domain,#severity,#reject_media,#reject_reports,#public_comment,#obfuscate).
  module IftasDni
    SOURCE = "iftas_dni"
    DEFAULT_CSV_URL = "https://docs.google.com/spreadsheets/d/1ZdYPSmQH0rO4K9Pp1AmbRu9G1kFnmjuj0X-4bZ4x3hI/gviz/tq?tqx=out:csv&gid=0&range=A:F"

    # A truncated or empty response must not be read as "the list is now
    # empty" -- that would delete every synced block. The list has run ~100
    # rows for a while; anything far short of that is the download failing,
    # not the list shrinking.
    MINIMUM_ROWS = 20

    # The list carries one sentinel row ("dni.invalid", tagged iftas:canary)
    # so subscribers can verify they're actually pulling it -- not a real
    # domain to block. Its absence is itself a signal: a response with every
    # row but the canary is exactly what a stale cache, a wrong sheet, or an
    # upstream format change would look like, and MINIMUM_ROWS alone would
    # wave it through.
    CANARY_TAG = "iftas:canary"

    module_function

    # Only #severity=suspend is meaningful to DomainPolicy's binary block; a
    # future row with a lighter severity (e.g. silence) is skipped rather
    # than promoted into a hard block.
    def parse(csv_text)
      canary_seen = false

      entries = CSV.parse(csv_text, headers: true).filter_map do |row|
        comment = row["#public_comment"].to_s
        tags = comment.split(";").map(&:strip)

        if tags.include?(CANARY_TAG)
          canary_seen = true
          next
        end

        domain = row["#domain"].to_s.strip.downcase
        next if domain.blank? || row["#severity"].to_s.strip != "suspend"

        { domain:, reason: comment.presence }
      end

      unless canary_seen
        raise "canary row (#{CANARY_TAG}) missing; the list may be truncated, cached, or not the DNI sheet"
      end

      entries
    end
  end
end
