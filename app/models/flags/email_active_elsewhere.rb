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
  #
  # Only addresses confirmed on BOTH sides match. An unconfirmed address is just
  # what someone typed, and with Mastodon's "postpone confirmation emails" it can
  # stay that way indefinitely. Matching on it would tell moderators which other
  # instance a stranger's address is on, or tell them the person in front of them
  # applied somewhere they never did, and this flag names the instance. It is
  # context rather than a verdict, so unlike Flags::Reapplication there is no
  # milder form worth that disclosure: it stays silent.
  #
  # Sync stops listing an account at its decision, so one approved before it
  # confirmed does not count until we learn that it has.
  class EmailActiveElsewhere < Rule
    include Flags::CrossInstanceFlag

    def call
      return nil unless request.instance.participating?
      return nil if request.canonical_email_hash.blank?
      return nil unless request.confirmed?

      matches = self.class.counterparts(request)
      return nil if matches.empty?

      detect(:warning, count: matches.size, instances: matches.map { it.instance.domain }.uniq)
    end

    # Active requests elsewhere with this canonical address confirmed, restricted
    # to instances that participate. Also used in reverse, to refresh the flag on
    # the other side when a new signup arrives here, which is why it does not ask
    # whether `request` itself is confirmed: that is #call's question, and the
    # caller may pass an unsaved probe that carries only the old address.
    def self.counterparts(request)
      return RegistrationRequest.none if request.canonical_email_hash.blank?

      RegistrationRequest
        .active
        .email_confirmed
        .where(canonical_email_hash: request.canonical_email_hash)
        .where.not(instance_id: request.instance_id)
        .joins(:instance)
        .merge(Instance.participating)
        .includes(:instance)
        .to_a
    end
  end
end
