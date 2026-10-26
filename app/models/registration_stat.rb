# How many people signed up to one instance in one hour, and what became of
# them. Counts only, nothing about any applicant, so these rows outlive the
# requests they were counted from: see RollUpRegistrationStatsJob.
class RegistrationStat < ApplicationRecord
  # The counters, in the order a chart stacks them. The statuses come straight
  # from RegistrationRequest::STATUSES, one column each.
  OUTCOMES = RegistrationRequest::STATUSES
  COUNTERS = [ "signups", *OUTCOMES, "flagged", "signalled" ].freeze

  belongs_to :instance
end
