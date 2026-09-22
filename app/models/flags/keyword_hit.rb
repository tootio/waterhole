module Flags
  class KeywordHit < Rule
    def call
      # Iterate over every field in isolation to make anchored regexes like e.g. "crypto$" work
      # This is up to four times the work, so we might want to revise this decision later.
      texts = [ request.invite_request, request.bio, request.display_name, request.username ].compact
      return nil if texts.blank?

      rules = request.instance.keyword_rules.enabled.select { |r| texts.any? { |t| r.matches?(t) } }
      return nil if rules.empty?

      detect(rules.max_by { |r| Flag.severities.fetch(r.severity) }.severity,
        patterns: rules.map(&:pattern))
    end
  end
end
