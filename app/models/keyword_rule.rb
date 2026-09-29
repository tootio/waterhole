# A watchword an instance's moderators check their own applicants against.
#
# Always per instance. There are deliberately no deployment-wide rules: every
# instance's moderators may edit their rules, so a shared rule would let one
# instance rewrite what flags every other instance's queue.
class KeywordRule < ApplicationRecord
  MATCH_TYPES = %w[substring word regex].freeze
  # The applicant's texts a watchword can be checked against, in the order
  # forms and lists show them. Each is checked on its own, so an anchored
  # regex like "crypto$" means the end of that field.
  FIELDS = {
    "invite_request" => "Join reason",
    "bio"            => "Profile note",
    "display_name"   => "Display name",
    "username"       => "Username"
  }.freeze
  # A user-supplied regex runs against every pending request on every sync, so
  # catastrophic backtracking would hang a worker. Ruby 3.2+ can bound it.
  REGEX_TIMEOUT = 0.25

  belongs_to :instance

  enum :match_type, MATCH_TYPES.index_by(&:itself), validate: true
  enum :severity, Flag::SEVERITIES, validate: true

  validates :pattern, presence: true
  validate  :regex_compiles
  validate  :fields_present

  scope :enabled, -> { where(enabled: true) }

  # A multiple select submits a blank first entry so that choosing nothing
  # still sends the parameter; order is the form's, not the click order.
  def fields=(values)
    super(FIELDS.keys & Array(values).map(&:to_s))
  end

  def checks?(field) = fields.include?(field.to_s)

  def field_labels = fields.map { FIELDS.fetch(it) }

  def matches?(text)
    return false if text.blank?

    case match_type
    when "substring" then text.downcase.include?(pattern.downcase)
    when "word"      then text.match?(/\b#{Regexp.escape(pattern)}\b/i)
    when "regex"     then matches_regex?(text)
    else false
    end
  end

  def match_indices(text)
    return [] if text.blank?

    regexp = to_regexp
    return [] unless regexp

    indices = []
    text.scan(regexp) do
      m = Regexp.last_match
      off = m&.offset(0)
      indices << off if off && off.first < off.second # nothing to highlight for empty matches
    end
    indices
  rescue Regexp::TimeoutError, RegexpError
    []
  end

  private

  def to_regexp
    return nil if pattern.blank?

    @to_regexp ||= begin
      case match_type
      when "substring" then Regexp.new(Regexp.escape(pattern), Regexp::IGNORECASE, timeout: REGEX_TIMEOUT)
      when "word"      then Regexp.new("\\b#{Regexp.escape(pattern)}\\b", Regexp::IGNORECASE, timeout: REGEX_TIMEOUT)
      when "regex"     then Regexp.new(pattern, Regexp::IGNORECASE, timeout: REGEX_TIMEOUT)
      end
    rescue Regexp::TimeoutError, RegexpError
      # we do not care that this error does not get memoized. Invalid regex patterns are validated on creation.
      nil
    end
  end

  def matches_regex?(text)
    Regexp.new(pattern, Regexp::IGNORECASE, timeout: REGEX_TIMEOUT).match?(text)
  rescue Regexp::TimeoutError, RegexpError
    false
  end

  def fields_present
    errors.add(:fields, "must include at least one field") if fields.blank?
  end

  def regex_compiles
    return unless match_type == "regex" && pattern.present?

    Regexp.new(pattern)
  rescue RegexpError => e
    errors.add(:pattern, "is not a valid regular expression (#{e.message})")
  end
end
