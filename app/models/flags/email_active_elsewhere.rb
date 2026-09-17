module Flags
  # Is this person currently using the same address on another instance that
  # moderates through this Waterhole?
  #
  # Matching is on the CANONICAL address, so foo+tag@gmail.com and f.o.o@gmail.com
  # do not read as different applicants.
  #
  # Reciprocity is the privacy design, not a nicety. This correlates applicants
  # across instances that may share nothing but a Waterhole deployment, so an
  # instance only SEES the signal if it also CONTRIBUTES: both sides of every
  # match must have opted in. That is why the opt-in is checked on the subject's
  # instance *and* joined onto the candidates.
  class EmailActiveElsewhere < Rule
    def call
      return nil unless request.instance.participating?
      return nil if request.canonical_email_hash.blank?

      matches = self.class.counterparts(request)
      return nil if matches.empty?

      detect(:warning, count: matches.size, instances: matches.map { it.instance.domain }.uniq)
    end

    # Active requests elsewhere sharing this canonical address, restricted to
    # instances that participate. Also used in reverse, to refresh the flag on
    # the other side when a new signup arrives here.
    def self.counterparts(request)
      return RegistrationRequest.none if request.canonical_email_hash.blank?

      RegistrationRequest
        .active
        .where(canonical_email_hash: request.canonical_email_hash)
        .where.not(instance_id: request.instance_id)
        .joins(:instance)
        .merge(Instance.participating)
        .includes(:instance)
        .to_a
    end
  end
end
