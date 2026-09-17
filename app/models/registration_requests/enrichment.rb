module RegistrationRequests
  # Country and ASN for the signup address.
  #
  # Done at observation time rather than lazily: Flags::Recompute must stay a
  # pure function of the database. A rule reading a file whose contents change
  # daily would silently rewrite flags on rows nobody touched, and sync calls
  # Recompute on every pass.
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
        ip_relay: relay_for(record.ip.to_s),
        # Stamped even when the databases had nothing, so "we looked and found
        # nothing" is distinguishable from "we never looked" and a re-sync does
        # not redo the lookup on every pass.
        ip_enriched_at: Time.current
      )
      record
    end

    # An address is never both, so the first list that has it decides.
    def relay_for(address)
      if Ip::PrivateRelay.include?(address) then "private_relay"
      elsif Ip::TorRelays.include?(address) then "tor"
      end
    end

    def needs_enrichment?(record)
      return false if record.ip.blank?

      record.ip_changed? || record.ip_enriched_at.nil?
    end
  end
end
