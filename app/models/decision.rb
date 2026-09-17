# A moderator's approve/reject, plus the state of pushing it back to Mastodon.
#
# Kept apart from RegistrationRequest because a decision is an event with sync
# state -- it can fail, be retried, and conflict with Mastodon -- while the
# request row stays a clean projection of Mastodon's state.
class Decision < ApplicationRecord
  ACTIONS = %w[approve reject].freeze
  STATES  = %w[pending succeeded failed conflict].freeze

  belongs_to :registration_request
  belongs_to :moderator

  # `action` collides with nothing on the model, but `enum :action` would define
  # Decision.approve as a scope; keep the explicit prefix for clarity.
  enum :action, ACTIONS.index_by(&:itself), prefix: :action, validate: true
  enum :state, STATES.index_by(&:itself), prefix: :state, validate: true

  # One live decision per request -- also the double-submit guard.
  validates :registration_request_id, uniqueness: true

  def approve? = action_approve?

  def resolved_status
    action_approve? ? "approved" : "rejected"
  end
end
