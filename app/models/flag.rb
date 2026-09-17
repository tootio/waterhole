# One automated signal on a request.
#
# A table rather than a jsonb blob because the queue filters and sorts by flag,
# which is a plain join here and a containment query with a GIN index otherwise.
class Flag < ApplicationRecord
  SEVERITIES = { info: 0, warning: 1, critical: 2 }.freeze

  belongs_to :registration_request, counter_cache: :flags_count

  enum :severity, SEVERITIES, validate: true

  validates :rule, presence: true, uniqueness: { scope: :registration_request_id }

  scope :by_severity, -> { order(severity: :desc) }

  # Rule names are identifiers; config/locales/en.yml holds what people read.
  def self.label_for(rule) = I18n.t("flags.#{rule}.label")

  def label = self.class.label_for(rule)

  def explanation = I18n.t("flags.#{rule}.explanation", **details.symbolize_keys, default: "")
end
