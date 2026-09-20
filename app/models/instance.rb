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
  has_many :purged_registrations, dependent: :delete_all

  # The moderator whose token background sync borrows, since jobs have no
  # logged-in user. Decisions never use this -- they use the deciding moderator.
  belongs_to :sync_moderator, class_name: "Moderator", optional: true

  enum :status, STATUSES.index_by(&:itself), validate: true

  # Stamped when access ends by revocation or block, and cleared when the
  # instance is verified again (see #access_ended_since).
  before_save :track_access_end, if: :will_save_change_to_status?

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

  # The admin's half of the two keys just turned; the operator holds the other.
  after_update_commit -> { OperatorMailer.signals_requested(self).deliver_later },
    if: :signals_request_arrived?

  def base_url = "https://#{domain}"

  # The navigation badge counts this instance's queue, not any one moderator's
  # view of it, so -- unlike the queue itself, which needs each viewer's own
  # session to render Claim vs Release -- it renders correctly from a job with
  # no session at all. That is what lets it be replaced in place instead of
  # refreshing whatever page the viewer happens to be on, which for someone
  # halfway through writing a watchword would be a refresh they did not ask for.
  #
  # The partial counts at render time, in the job, so the number is the one true
  # when it arrives rather than when it was enqueued.
  def broadcast_queue_badge_later
    broadcast_replace_later_to [ self, :queue_badge ],
      target: "queue_badge", partial: "shared/queue_badge", locals: { instance: self }
  end

  # The per-record form of the participating scope, for the subject side of the
  # cross-instance rules: an instance that no longer contributes (revoked,
  # blocked, past its terms grace, or opted out) must not keep seeing.
  def participating? = signals_opted_in? && signals_approved? && admitted?

  # Waiting on the operator only: the record opts in, access is fine, and
  # approval has not been given. Only on the change, so the hourly re-check
  # re-reading the same record does not mail again.
  def signals_request_arrived?
    saved_change_to_signals_opted_in?(to: true) && !signals_approved? && admitted? &&
      Waterhole::Deployment.operator_notifications?
  end

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
    LegalDocuments.changed_since(accepted_terms_digest)
  end

  # Sync borrows a moderator's personal token. Prefer the most recently
  # authenticated one whose token is not known-dead.
  def sync_token_holder
    return sync_moderator if sync_moderator&.lends_token?

    moderators.lending_token.order(last_authenticated_at: :desc).first
  end

  # Since when this instance has been without access, or nil while it has it.
  # A lapsed terms grace window ends access without any status change -- only
  # time passes -- so its deadline is the moment.
  def access_ended_since
    return access_ended_at if revoked? || blocked?
    return terms_grace_until if terms_grace_expired?

    nil
  end

  def rotate_sync_moderator!
    holder = moderators.lending_token.order(last_authenticated_at: :desc).first
    update!(sync_moderator: holder)
    holder
  end

  def revoke!(reason:, status: :revoked)
    transaction do
      update!(status: status, verification_detail: reason)
      Session.terminate_all(Session.where(moderator: moderators))
    end
  end

  private

  def track_access_end
    if revoked? || blocked?
      self.access_ended_at ||= Time.current
    elsif verified?
      self.access_ended_at = nil
    end
  end
end
