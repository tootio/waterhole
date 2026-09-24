# A moderator's approve/reject vote on a request. Advice to the team only: it
# never reaches Mastodon -- that is what a Decision does.
class Vote < ApplicationRecord
  VOTES = %w[approve reject].freeze

  belongs_to :registration_request
  belongs_to :moderator

  enum :vote, VOTES.index_by(&:itself), prefix: :vote, validate: true

  # One vote per moderator per request; the unique index backs this up.
  validates :moderator_id, uniqueness: { scope: :registration_request_id }
end
