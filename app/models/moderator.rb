# A person who moderates one instance. Identity and authority both come from
# Mastodon: we store their personal OAuth token and let Mastodon's role
# permissions decide what they may actually do.
class Moderator < ApplicationRecord
  encrypts :access_token

  belongs_to :instance
  has_many :sessions, dependent: :destroy
  # All three columns are NOT NULL: a moderator with notes, decisions or votes
  # is anonymised by forget!, never destroyed.
  has_many :notes, dependent: :restrict_with_exception
  has_many :decisions, dependent: :restrict_with_exception
  has_many :votes, dependent: :restrict_with_exception
  has_one :avatar, dependent: :delete

  validates :mastodon_account_id, presence: true,
    uniqueness: { scope: :instance_id }
  validates :username, presence: true

  scope :token_usable, -> { where(token_invalidated_at: nil).where.not(access_token: nil) }
  # Background sync borrows a moderator's token; only from someone who agreed
  # to their data being processed.
  scope :lending_token, -> { token_usable.where.not(consented_at: nil) }
  # Not yet anonymised by forget!.
  scope :remembered, -> { where.not("mastodon_account_id LIKE 'forgotten-%'") }

  # The still image: never animated, and the one Waterhole copies (see AvatarFetcher).
  def self.avatar_url_from(account) = account["avatar_static"].presence || account["avatar"].presence

  def token_usable? = token_invalidated_at.nil? && access_token.present?

  # Last signed in before sign-in asked for read:search (see
  # Instances::ProveIdentity), so Mastodon will show its authorize screen once
  # more, and afterwards list Waterhole twice among their authorized apps.
  def reauthorization_pending?
    token_scopes.present? && !token_scopes.split.include?(Mastodon::OAuth::SEARCH_SCOPE)
  end

  def lends_token? = token_usable? && consented_at.present?

  # Consent is to the privacy policy as it stands, so a change to it asks again.
  def consent_current?
    consented_at.present? &&
      (LegalDocuments.privacy_digest.nil? || consented_privacy_digest == LegalDocuments.privacy_digest)
  end

  def consent!
    update!(consented_at: Time.current, consented_privacy_digest: LegalDocuments.privacy_digest)
    instance.update!(sync_moderator: self) if instance.sync_moderator_id.blank?
    refresh_avatar_later
  end

  # Copies the avatar again whenever Mastodon reports a different one (or none).
  def refresh_avatar_later
    FetchModeratorAvatarJob.perform_later(self) if consent_current? && stored_avatar_url != avatar_url
  end

  # Without loading the image itself.
  def stored_avatar_url = Avatar.where(moderator_id: id).pick(:source_url)

  # Changes whenever the stored image does, so the browser may cache each one
  # for good; nil when there is none to show.
  def avatar_version = Avatar.where(moderator_id: id).pick(:updated_at)&.strftime("%s%6N")

  # A moderator who declines consent: sign them out and keep nothing about
  # them. The record goes -- or, where notes, decisions and votes still point
  # at it, stays as an anonymous "former moderator": those belong to requests
  # still in the queue (they go when the request is purged), and the columns
  # are NOT NULL. Votes stay too, so a tally does not shift under the team.
  def forget!
    transaction do
      Session.terminate_all(sessions)
      RegistrationRequest.where(claimed_by_id: id).update_all(claimed_by_id: nil, claimed_at: nil)

      # Before anything that removes the row: instances.sync_moderator_id
      # points at it. With the token gone, rotation cannot pick this one again.
      update!(access_token: nil, token_invalidated_at: Time.current)
      Avatar.where(moderator_id: id).delete_all
      instance.rotate_sync_moderator! if instance.sync_moderator_id == id

      if notes.exists? || decisions.exists? || votes.exists?
        update!(mastodon_account_id: "forgotten-#{id}", username: "former-moderator",
          display_name: nil, avatar_url: nil, profile_url: nil, role_name: nil, token_scopes: nil,
          last_authenticated_at: nil, consented_at: nil, consented_privacy_digest: nil)
      else
        destroy!
      end
    end
  end

  def handle = "@#{username}@#{instance.domain}"

  def name = display_name.presence || username

  # Called when Mastodon answers 401: the token is dead, so the sessions
  # resting on it are too.
  def invalidate_token!
    transaction do
      update!(token_invalidated_at: Time.current)
      Session.terminate_all(sessions)
      instance.rotate_sync_moderator! if instance.sync_moderator_id == id
    end
  end
end
