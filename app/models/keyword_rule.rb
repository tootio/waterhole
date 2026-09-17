# A watchword an instance's moderators check their own applicants against.
#
# Always per instance. There are deliberately no deployment-wide rules: every
# instance's moderators may edit their rules, so a shared rule would let one
# instance rewrite what flags every other instance's queue.
class KeywordRule < ApplicationRecord
  MATCH_TYPES = %w[substring word regex].freeze
  # A user-supplied regex runs against every pending request on every sync, so
  # catastrophic backtracking would hang a worker. Ruby 3.2+ can bound it.
  REGEX_TIMEOUT = 0.25

  belongs_to :instance

  enum :match_type, MATCH_TYPES.index_by(&:itself), validate: true
  enum :severity, Flag::SEVERITIES, validate: true

  validates :pattern, presence: true
  validate  :regex_compiles

  scope :enabled, -> { where(enabled: true) }

  def matches?(text)
    return false if text.blank?

    case match_type
    when "substring" then text.downcase.include?(pattern.downcase)
    when "word"      then text.match?(/\b#{Regexp.escape(pattern)}\b/i)
    when "regex"     then matches_regex?(text)
    else false
    end
  end

  private

  def matches_regex?(text)
    Regexp.new(pattern, Regexp::IGNORECASE, timeout: REGEX_TIMEOUT).match?(text)
  rescue Regexp::TimeoutError, RegexpError
    false
  end

  def regex_compiles
    return unless match_type == "regex" && pattern.present?

    Regexp.new(pattern)
  rescue RegexpError => e
    errors.add(:pattern, "is not a valid regular expression (#{e.message})")
  end
end
