module Flags
  class KeywordHit < Rule
    def call
      text = [ request.invite_request, request.bio, request.display_name ].compact.join("\n")
      return nil if text.blank?

      rules = request.instance.keyword_rules.enabled.select { |r| r.matches?(text) }
      return nil if rules.empty?

      detect(rules.max_by { |r| Flag.severities.fetch(r.severity) }.severity,
        patterns: rules.map(&:pattern))
    end
  end
end
