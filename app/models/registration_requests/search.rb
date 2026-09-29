module RegistrationRequests
  # The queue's free-text search.
  #
  #   crypto                 a word anywhere: username, display name, email domain or join reason
  #   reason:crypto          only in that field (FIELDS)
  #   -domain:gmail.com      a leading - excludes instead
  #   reason:"free followers"  quotes keep a phrase together
  #   flag:disposable_email  requests with that flag (its rule name or label)
  #   flag:keyword_hit@warning  …with that flag at warning or above
  #   severity:critical      requests with any flag at critical or above
  #
  # Terms combine with AND. Anything that is not one of these -- an unknown
  # property, a stray colon in a URL -- is searched for as plain text, so no
  # input is an error.
  class Search
    FIELDS = {
      "username" => "registration_requests.username",
      "name"     => "registration_requests.display_name",
      "domain"   => "registration_requests.email_domain",
      "reason"   => "registration_requests.invite_request",
      "bio"      => "registration_requests.bio"
    }.freeze
    # What a plain word is looked for in: the fields a moderator sees in the
    # queue. The bio needs asking for.
    ANYWHERE = FIELDS.values_at("username", "name", "domain", "reason").freeze
    PROPERTIES = (FIELDS.keys + %w[flag severity]).freeze
    SEVERITIES = Flag::SEVERITIES.keys.map(&:to_s).freeze

    # severity: the lowest a flag: term's flag may have, or nil for any.
    Term = Data.define(:property, :value, :negated, :severity)

    # An optional -, an optional property:, then a "quoted phrase" (closing
    # quote optional while typing, @severity optional after it) or a run of
    # non-space characters.
    TOKEN = /(-)?(?:([a-z_]+):)?(?:"([^"]*)"?(?:@([a-z]+))?|(\S+))/i

    attr_reader :terms

    def initialize(text)
      @terms = self.class.parse(text.to_s)
    end

    def self.parse(text)
      text.scan(TOKEN).filter_map do |negation, property, phrase, phrase_severity, word|
        property = property&.downcase
        value, severity = split_severity(phrase || word, phrase_severity, quoted: !phrase.nil?)
        # Only a flag: term has a severity; anywhere else the suffix is text.
        value, severity = "#{value}@#{severity}", nil if severity && property != "flag"
        # Not ours: keep the text as typed ("http://…" stays one word).
        unless PROPERTIES.include?(property) && (property != "severity" || SEVERITIES.include?(value.downcase))
          value = "#{property}:#{value}" if property
          property = nil
        end
        next if value.strip.empty?

        Term.new(property:, value: property == "severity" ? value.downcase : value.strip,
          negated: negation.present?, severity:)
      end
    end

    # "name@warning" -> ["name", "warning"]; a suffix that names no severity
    # stays part of the value.
    def self.split_severity(value, phrase_severity, quoted:)
      suffix = quoted ? phrase_severity : value[/@([a-z]+)\z/i, 1]
      return [ value, nil ] if suffix.nil?
      return [ quoted ? "#{value}@#{suffix}" : value, nil ] unless SEVERITIES.include?(suffix.downcase)

      [ quoted ? value : value.delete_suffix("@#{suffix}"), suffix.downcase ]
    end

    def apply(relation)
      terms.inject(relation) do |scope, term|
        case term.property
        when "flag"     then flagged(scope, term)
        when "severity" then restrict(scope, Flag.at_least(term.value), term)
        else matching(scope, term)
        end
      end
    end

    private

    # COALESCE, so an empty field is "does not contain" rather than NULL,
    # which NOT would carry through and drop the row from both sides.
    def matching(scope, term)
      columns = term.property ? [ FIELDS.fetch(term.property) ] : ANYWHERE
      condition = columns.map { "COALESCE(#{it}, '') ILIKE :pattern" }.join(" OR ")
      pattern = "%#{RegistrationRequest.sanitize_sql_like(term.value)}%"

      term.negated ? scope.where.not(condition, pattern:) : scope.where(condition, pattern:)
    end

    def flagged(scope, term)
      rule = flag_rule(term.value)
      return (term.negated ? scope : scope.none) if rule.nil?

      restrict(scope, Flag.where(rule:).at_least(term.severity), term)
    end

    # Requests carrying one of these flags, or none of them when negated.
    def restrict(scope, flags, term)
      ids = flags.select(:registration_request_id)
      term.negated ? scope.where.not(id: ids) : scope.where(id: ids)
    end

    # The rule name, or its label as moderators see it: "Disposable email",
    # disposable-email and disposable_email all name the same rule.
    def flag_rule(value)
      key = value.downcase.gsub(/[\s-]+/, "_")
      Flags.rule_names.find { it == key || Flag.label_for(it).downcase.gsub(/[\s-]+/, "_") == key }
    end
  end
end
