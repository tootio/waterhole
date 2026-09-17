# A person who moderates one instance. Identity and authority both come from
# Mastodon: we store their personal OAuth token and let Mastodon's role
# permissions decide what they may actually do.
class Moderator < ApplicationRecord
  encrypts :access_token

  belongs_to :instance
  has_many :sessions, dependent: :destroy
  has_many :notes, dependent: :nullify
  has_many :decisions, dependent: :nullify

  validates :mastodon_account_id, presence: true,
    uniqueness: { scope: :instance_id }
  validates :username, presence: true

  scope :token_usable, -> { where(token_invalidated_at: nil).where.not(access_token: nil) }

  def token_usable? = token_invalidated_at.nil? && access_token.present?

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
