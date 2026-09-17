# Moderator discussion on a request. Threading is capped at one level: a root
# note plus replies. Arbitrary nesting buys nothing for triage and costs
# recursive rendering, recursive broadcast targets and CTE queries.
class Note < ApplicationRecord
  belongs_to :registration_request, counter_cache: :notes_count
  belongs_to :moderator
  belongs_to :parent, class_name: "Note", optional: true

  has_many :replies, class_name: "Note", foreign_key: :parent_id, dependent: :destroy

  validates :body, presence: true, length: { maximum: 10_000 }
  validate  :threading_depth_is_one
  validate  :parent_on_same_request

  # Notes append rather than refresh: an appended note renders identically for
  # everyone, so it needs no session, and appending is smoother than a morph for
  # a chat-like thread. It also avoids morphing away a half-typed reply.
  after_create_commit :broadcast_to_thread

  scope :roots, -> { where(parent_id: nil) }
  scope :chronological, -> { order(created_at: :asc) }

  def root? = parent_id.nil?

  def edited? = edited_at.present?

  private

  def broadcast_to_thread
    target = parent_id.present? ? "replies_#{parent_id}" : "notes"
    broadcast_append_later_to registration_request, target: target,
      partial: "notes/note", locals: { note: self }
  end

  def threading_depth_is_one
    return if parent.nil? || parent.root?

    errors.add(:parent, "cannot reply to a reply")
  end

  # parent_id arrives from the form, and replies render under their parent --
  # so without this a reply could be planted in any thread, on any instance,
  # by guessing a note id.
  def parent_on_same_request
    return if parent_id.nil? || parent&.registration_request_id == registration_request_id

    errors.add(:parent, "must be a note on the same request")
  end
end
