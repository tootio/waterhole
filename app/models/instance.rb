# A Mastodon server Waterhole mirrors a registration queue for.
#
# Admission is two gates that must BOTH open (see Admission):
#   1. the operator's allow/blocklist  -- will this Waterhole serve the domain?
#   2. a DNS TXT record on the domain  -- does that instance want this Waterhole?
class Instance < ApplicationRecord
  STATUSES = %w[unverified verified terms_outdated revoked blocked].freeze

  encrypts :client_secret

  has_many :moderators, dependent: :destroy
  has_many :registration_requests, dependent: :destroy
  has_many :keyword_rules, dependent: :destroy
  has_many :sync_runs, dependent: :destroy

  # The moderator whose token background sync borrows, since jobs have no
  # logged-in user. Decisions never use this -- they use the deciding moderator.
  belongs_to :sync_moderator, class_name: "Moderator", optional: true

  enum :status, STATUSES.index_by(&:itself), validate: true

  normalizes :domain, with: ->(d) { d.to_s.strip.downcase.delete_prefix("https://").delete_prefix("http://").chomp("/") }

  validates :domain, presence: true, uniqueness: true,
    format: { with: /\A(?=.{1,253}\z)[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/,
              message: "must be a bare hostname such as mastodon.example" }

  # Includes instances inside their terms grace window: "keeps working until the
  # deadline" has to mean sync too, not just sign-in.
  scope :syncable, -> {
    where(status: "verified").or(
      where(status: "terms_outdated").where(terms_grace_until: Time.current..)
    )
  }

  # Contributes to, and may see, cross-instance signals. Reciprocity means this
  # is the only scope either cross-instance rule should match against.
  #
  # Two keys, held by different people. The admin's consent is in DNS, so only
  # whoever controls the domain can give it and removing it takes effect on the
  # next check. The operator's approval stops a stranger with a domain and a
  # fake Mastodon server from joining just to probe everyone else's applicants.
  scope :participating, -> { syncable.where(signals_opted_in: true, signals_approved: true) }

  # Joining or leaving the participating set changes what every other instance's
  # cross-instance flags should say. The hourly sweep would catch it anyway;
  # this makes a revocation or an opt-out take effect in minutes instead.
  after_update_commit -> { RefreshCrossInstanceFlagsJob.perform_later },
    if: -> { saved_change_to_status? || saved_change_to_signals_opted_in? || saved_change_to_signals_approved? }

  def base_url = "https://#{domain}"

  # The per-record form of the participating scope, for the subject side of the
  # cross-instance rules: an instance that no longer contributes (revoked,
  # blocked, past its terms grace, or opted out) must not keep seeing.
  def participating? = signals_opted_in? && signals_approved? && admitted?

  # Waterhole only talks to a server the instance admin has vouched for by DNS
  # and the operator has not blocked.
  # Re-registering when the redirect_uri still matches would orphan an app on the
  # instance and clutter its admin list; NOT re-registering when it has changed
  # breaks token exchange for everyone at once.
  def oauth_app_current?
    client_id.present? && client_secret.present? &&
      redirect_uri == Mastodon::OAuth.redirect_uri
  end

  # Waterhole only talks to a server whose admin has vouched for it by DNS and
  # which the operator has not blocked.
  #
  # A stale-terms instance keeps working until its grace window closes. The
  # status stays `terms_outdated` afterwards rather than becoming `revoked`,
  # because the record is still published and the fix is a different one.
  def admitted?
    return true if verified?
    return terms_grace_active? if terms_outdated?

    false
  end

  # Has this instance ever been verified under some version of the terms? Used to
  # decide whether it has earned a grace window.
  def ever_accepted_terms? = verified_at.present?

  def terms_grace_active? = terms_grace_until.present? && terms_grace_until.future?

  def terms_grace_expired? = terms_outdated? && !terms_grace_active?

  def terms_grace_remaining
    return nil unless terms_grace_active?

    terms_grace_until - Time.current
  end

  # Which documents changed since this instance last accepted, for the UI.
  def outdated_documents
    return LegalDocuments.published if accepted_terms_digest.blank?

    LegalDocuments.published.reject { it.digest == accepted_terms_digest }
  end

  # Sync borrows a moderator's personal token. Prefer the most recently
  # authenticated one whose token is not known-dead.
  def sync_token_holder
    return sync_moderator if sync_moderator&.token_usable?

    moderators.token_usable.order(last_authenticated_at: :desc).first
  end

  def rotate_sync_moderator!
    holder = moderators.token_usable.order(last_authenticated_at: :desc).first
    update!(sync_moderator: holder)
    holder
  end

  def revoke!(reason:, status: :revoked)
    transaction do
      update!(status: status, verification_detail: reason)
      Session.terminate_all(Session.where(moderator: moderators))
    end
  end
end
