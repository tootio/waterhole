module Flags
  # The join reason is nearly identical to other requests' -- the template a
  # signup farm fills in, whatever address each signup comes from. Compared by
  # fingerprint (ReasonFingerprint), never by text.
  #
  # One match is `info`: two people can write the same thing. Several is the
  # pattern of a farm.
  class SimilarReason < Rule
    CAP = 25

    def call
      matches = self.class.counterparts(request)
      return nil if matches.empty?

      own, elsewhere = matches.partition { it.instance_id == request.instance_id }
      # Usernames only from this instance's own queue; elsewhere, the domain.
      detect(matches.size >= 2 ? :warning : :info,
        count: matches.size, capped: matches.size >= CAP,
        usernames: own.map(&:username).first(6),
        instances: elsewhere.map { it.instance.domain }.uniq)
    end

    def self.counterparts(request)
      return RegistrationRequest.none if request.invite_fingerprint.nil?

      Flags.comparable_requests(request.instance)
        .where.not(id: request.id)
        .where.not(invite_fingerprint: nil)
        .where("bit_count((invite_fingerprint # ?)::bit(64)) <= ?",
          request.invite_fingerprint, ReasonFingerprint::MAX_DISTANCE)
        .includes(:instance).limit(CAP).to_a
    end
  end
end
