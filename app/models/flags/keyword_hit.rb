module Flags
  # The applicant's texts match one or more of the instance's watchwords, each
  # checked only against the fields it names (KeywordRule#fields).
  #
  # rule_ids let the queue filter by watchword (RegistrationRequest
  # .with_watchwords); the patterns stay for reading, since a watchword can be
  # edited or deleted after it flagged someone.
  class KeywordHit < Rule
    def call
      texts = KeywordRule::FIELDS.keys.filter_map do |field|
        text = request.public_send(field)
        [ field, text ] if text.present?
      end
      return nil if texts.empty?

      rules = request.instance.keyword_rules.enabled.select do |rule|
        texts.any? { |field, text| rule.checks?(field) && rule.matches?(text) }
      end
      return nil if rules.empty?

      detect(rules.max_by { |r| Flag.severities.fetch(r.severity) }.severity,
        patterns: rules.map(&:pattern), rule_ids: rules.map(&:id))
    end
  end
end
