module RegistrationRequests
  # Country and ASN for the signup address.
  #
  # Done at observation time rather than lazily, for two reasons:
  #
  #   1. Flags::Recompute must stay a pure function of the database. A rule
  #      reading a file whose contents change daily would silently rewrite flags
  #      on rows nobody touched, and sync calls Recompute on every pass.
  #   2. PurgeResolvedRequestPiiJob clears `ip` after the retention window, so a
  #      lazy lookup would make historical rows retroactively lose the signal.
  #
  # Kept out of Mapper deliberately: that is a pure payload-to-attributes
  # function with no I/O, and it should stay that way.
  module Enrichment
    module_function

    def apply(record)
      return record unless needs_enrichment?(record)

      result = Ip::Lookup.call(record.ip.to_s)
      record.assign_attributes(
        ip_country: result&.country,
        ip_asn: result&.asn,
        ip_asn_org: result&.asn_org,
        # Stamped even when the databases had nothing, so "we looked and found
        # nothing" is distinguishable from "we never looked" and a re-sync does
        # not redo the lookup on every pass.
        ip_enriched_at: Time.current
      )
      record
    end

    def needs_enrichment?(record)
      return false if record.ip.blank?

      record.ip_changed? || record.ip_enriched_at.nil?
    end
  end
end
