# One pass of the sync job. Makes "why didn't this request show up?" answerable.
class SyncRun < ApplicationRecord
  STATUSES = %w[running succeeded failed].freeze

  belongs_to :instance

  enum :status, STATUSES.index_by(&:itself), validate: true

  scope :recent, -> { order(started_at: :desc) }

  # The filter on the history page. Anything that is not a real status -- "all",
  # a stale bookmark, a hand-edited URL -- means no filter rather than no rows.
  scope :with_status, ->(status) { STATUSES.include?(status.to_s) ? where(status: status) : all }

  scope :started_before, ->(time) { where(started_at: ..time) }

  def duration
    return nil unless finished_at

    finished_at - started_at
  end
end
