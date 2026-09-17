module Flags
  # Is this signup network currently in use on another instance that moderates
  # through this Waterhole?
  #
  # Matching uses the generated ip_group column: IPv4 exactly, IPv6 by /64,
  # because IPv6 hosts rotate their low bits constantly and exact matching would
  # miss almost every real repeat signup.
  #
  # Reciprocity is the privacy design, as with the email signal: an instance only
  # SEES this if it also CONTRIBUTES, so the opt-in is checked on the subject's
  # instance and joined onto the candidates.
  class IpActiveElsewhere < Rule
    # A shared /64 behind carrier-grade NAT could match hundreds of rows, and
    # counterparts also drives the reverse fan-out. The email rule needs no cap
    # because an address matches a handful.
    COUNTERPART_CAP = 25

    def call
      return nil unless request.instance.participating?
      return nil if request.ip_group.blank?

      matches = self.class.counterparts(request)
      return nil if matches.empty?

      # `info`, not `warning`: a shared address is close to an identity claim, but
      # a shared /64 can be a household, an office or a carrier block. Disclosing
      # a person's presence on another instance on that basis deserves the
      # quieter severity.
      detect(:info, count: matches.size, capped: matches.size >= COUNTERPART_CAP,
        scope: ipv6? ? "/64" : "exact",
        instances: matches.map { it.instance.domain }.uniq)
    end

    def ipv6? = request.ip&.ipv6?

    def self.counterparts(request)
      return RegistrationRequest.none if request.ip_group.blank?

      RegistrationRequest
        .active
        .where(ip_group: request.ip_group)
        .where.not(instance_id: request.instance_id)
        .joins(:instance)
        .merge(Instance.participating)
        .includes(:instance)
        .limit(COUNTERPART_CAP)
        .to_a
    end
  end
end
