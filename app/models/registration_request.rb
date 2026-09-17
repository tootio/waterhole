# A pending signup mirrored from Mastodon. This table is a projection of
# Mastodon's state; the local workflow (claims, notes, flags, decisions) hangs
# off it.
class RegistrationRequest < ApplicationRecord
  STATUSES = %w[pending approved rejected approved_elsewhere rejected_elsewhere expired].freeze
  RESOLVED_STATUSES = STATUSES - %w[pending]
  # "Currently used" for the cross-instance email signal.
  ACTIVE_STATUSES = %w[pending approved].freeze

  STALE_CLAIM_AFTER = 4.hours

  # Mastodon's Scheduler::UserCleanupScheduler deletes accounts whose email is
  # still unconfirmed this long after the confirmation mail was sent.
  UNCONFIRMED_ACCOUNT_LIFETIME = 7.days

  encrypts :email, deterministic: true

  belongs_to :instance
  belongs_to :claimed_by, class_name: "Moderator", optional: true

  has_many :notes, dependent: :destroy
  has_many :flags, dependent: :destroy
  has_one  :decision, dependent: :destroy

  enum :status, STATUSES.index_by(&:itself), validate: true
  # Set by RegistrationRequests::Enrichment: ip_relay_private_relay?, ip_relay_tor?
  enum :ip_relay, %w[private_relay tor].index_by(&:itself), prefix: true, validate: { allow_nil: true }

  validates :mastodon_account_id, presence: true,
    uniqueness: { scope: :instance_id }
  validates :username, :signed_up_at, presence: true

  # Two subscriptions, two jobs.
  #
  # Both are REFRESH broadcasts rather than targeted replaces, and that is
  # deliberate: a broadcast rendered from a background job has no session, so
  # Current.moderator is nil and a targeted partial cannot render per-viewer
  # state -- "Claim" vs "Release" vs "Claimed by @bob" is exactly that. A refresh
  # makes each browser re-request the page with its OWN cookies, so every viewer
  # gets a correct personalised render, and Turbo coalesces them.
  broadcasts_refreshes_to ->(request) { [ request.instance, :registration_requests ] }
  after_update_commit -> { broadcast_refresh_later }

  before_validation :derive_email_fields
  # After the email fields: the signup shape includes the email domain.
  before_validation :derive_pattern_fields

  # ip_group is computed by Postgres, so the in-memory value is stale the moment
  # `ip` is saved -- and sync recomputes flags immediately after saving, which
  # would make both IP rules see a nil key on exactly the rows that just changed.
  # One cheap read, only when the address actually changed.
  after_save :refresh_ip_group, if: :saved_change_to_ip?

  # Cross-instance flags live on OTHER instances' requests, so a change here has
  # to reach them: joining or leaving the active set (a rejection, wherever it
  # happens), or a new email or network. The old key matters as much as the new
  # one -- a pending user who signs in from elsewhere must stop flagging the
  # requests that matched their previous network.
  before_save :remember_previous_ip_group, if: :ip_changed?
  after_commit :refresh_cross_instance_counterparts, on: %i[create update],
    if: :cross_instance_match_changed?

  # Order by signed_up_at, never by mastodon_account_id: snowflakes are decimal
  # STRINGS, so lexicographic order breaks across digit lengths.
  scope :newest_first, -> { order(signed_up_at: :desc) }
  scope :oldest_first, -> { order(signed_up_at: :asc) }
  scope :riskiest_first, -> { order(max_flag_severity: :desc, flags_count: :desc, signed_up_at: :asc) }

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :email_confirmed, -> { where(confirmed: true) }
  scope :email_unconfirmed, -> { where(confirmed: false) }
  scope :resolved, -> { where(status: RESOLVED_STATUSES) }
  scope :unclaimed, -> { where(claimed_by_id: nil) }
  scope :claimed, -> { where.not(claimed_by_id: nil) }
  scope :claimed_by_moderator, ->(m) { where(claimed_by: m) }
  scope :with_flag, ->(rule) { where(id: Flag.where(rule: rule).select(:registration_request_id)) }

  scope :search, ->(term) {
    term = term.to_s.strip
    next all if term.blank?

    pattern = "%#{sanitize_sql_like(term)}%"
    where("username ILIKE :p OR display_name ILIKE :p OR email_domain ILIKE :p OR invite_request ILIKE :p", p: pattern)
  }

  def claimed? = claimed_by_id.present?

  # Deletes the request and everything hanging off it -- the applicant's data,
  # notes, flags, claim and decision -- and keeps only Mastodon's account ID
  # (PurgedRegistration), so sync never imports it again. After the retention
  # period (PurgeResolvedRequestsJob), or on demand by a moderator.
  def purge!
    # Collected BEFORE deleting: afterwards nothing finds the rows on other
    # instances whose cross-instance flags cite this one, and their flags
    # would outlive the evidence, still naming a person whose data is gone.
    counterparts = Flags.cross_instance_rules.flat_map { it.counterparts(self) }.uniq(&:id)

    transaction do
      PurgedRegistration.find_or_create_by!(instance_id:, mastodon_account_id:)
      destroy!
    end

    counterparts.each { RecomputeFlagsJob.perform_later(it) }
  end

  def claim_stale? = claimed? && claimed_at < STALE_CLAIM_AFTER.ago

  def resolved? = RESOLVED_STATUSES.include?(status)

  # Resolved by someone acting directly in Mastodon rather than here.
  def resolved_elsewhere? = status.end_with?("_elsewhere")

  # What an account that now 404s in Mastodon most likely became. Mastodon
  # deletes the user both on rejection and when the email stays unconfirmed for
  # UNCONFIRMED_ACCOUNT_LIFETIME, and the 404 looks the same either way.
  #
  # signed_up_at stands in for when the confirmation mail was sent: resending it
  # only pushes deletion later, so "unconfirmed and older than the lifetime" is
  # when expiry is possible. Inside that window it can only be a rejection;
  # outside it, expiry is the likelier story -- rejecting an unconfirmed
  # account in Mastodon's own UI is the one case this misreads.
  def deleted_upstream_status
    if !confirmed? && signed_up_at <= UNCONFIRMED_ACCOUNT_LIFETIME.ago
      "expired"
    else
      "rejected_elsewhere"
    end
  end

  def account_age_at_signup = signed_up_at

  def invite_request_words = invite_request.to_s.split.size

  def recompute_flags! = Flags::Recompute.call(self)

  def active? = ACTIVE_STATUSES.include?(status)

  private

  def remember_previous_ip_group
    @previous_ip_group = attribute_in_database(:ip_group)
  end

  def cross_instance_match_changed?
    saved_change_to_canonical_email_hash? || saved_change_to_ip? ||
      saved_change_to_invite_fingerprint? || saved_change_to_signup_shape? ||
      (saved_change_to_status? && ACTIVE_STATUSES.include?(status_before_last_save) != active?)
  end

  def refresh_cross_instance_counterparts
    cross_instance_counterparts.each { RecomputeFlagsJob.perform_later(it) }
  ensure
    @previous_ip_group = nil
  end

  # Requests on other instances whose cross-instance flags depend on this one,
  # found under its current match keys and, when the last save changed them,
  # its previous ones -- via an unsaved probe carrying the old values.
  def cross_instance_counterparts
    probes = [ self ]
    old_hash  = canonical_email_hash_before_last_save if saved_change_to_canonical_email_hash?
    old_group = @previous_ip_group if saved_change_to_ip?
    old_fingerprint = invite_fingerprint_before_last_save if saved_change_to_invite_fingerprint?
    old_shape = signup_shape_before_last_save if saved_change_to_signup_shape?
    if [ old_hash, old_group, old_fingerprint, old_shape ].any?(&:present?)
      probes << self.class.new(instance_id:, signed_up_at:, canonical_email_hash: old_hash, ip_group: old_group,
        invite_fingerprint: old_fingerprint, signup_shape: old_shape)
    end

    Flags.cross_instance_rules
      .flat_map { |rule| probes.flat_map { rule.counterparts(it) } }
      .uniq(&:id)
  end

  def refresh_ip_group
    self[:ip_group] = self.class.where(id: id).pick(:ip_group)
    clear_attribute_change(:ip_group)
  end

  # email_domain stays plaintext because the disposable-domain flag and queue
  # filtering both need to query it; canonical_email_hash is the cross-instance
  # match key. The address itself is encrypted.
  def derive_email_fields
    return unless email_changed? || new_record?

    self.email_domain         = EmailCanonicalizer.domain_of(email)
    self.canonical_email_hash = EmailCanonicalizer.hash_for(email)
  end

  # Match keys for signup farms that rotate their addresses (the similar_reason
  # and signup_burst flags).
  def derive_pattern_fields
    self.invite_fingerprint = ReasonFingerprint.call(invite_request) if invite_request_changed? || new_record?
    if new_record? || email_domain_changed? || username_changed? || locale_changed?
      self.signup_shape = SignupShape.call(email_domain:, username:, locale:)
    end
  end
end
