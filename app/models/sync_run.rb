# One pass of the sync job. Makes "why didn't this request show up?" answerable.
class SyncRun < ApplicationRecord
  STATUSES = %w[running succeeded failed].freeze

  belongs_to :instance

  enum :status, STATUSES.index_by(&:itself), validate: true

  scope :recent, -> { order(started_at: :desc) }

  def duration
    return nil unless finished_at

    finished_at - started_at
  end
end
