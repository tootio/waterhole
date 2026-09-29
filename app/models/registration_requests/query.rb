module RegistrationRequests
  # Composes the queue's filters. Scopes live on the model; this only assembles
  # them, so the controller stays a controller.
  class Query
    SORTS   = %w[newest oldest risk].freeze
    CLAIMS  = %w[any unclaimed mine theirs].freeze
    # Unconfirmed signups are hidden by default, as in Mastodon, which only
    # tells staff about a pending account once its email is confirmed: many
    # never are, and Mastodon deletes them after a week.
    EMAILS  = %w[confirmed unconfirmed any].freeze
    # Several flags or watchwords: any of them (the default), or all.
    MATCHES = %w[any all].freeze
    # The lowest severity a chosen flag may have ("Warning and above").
    SEVERITIES = Flag::SEVERITIES.keys.map(&:to_s).freeze
    DEFAULT = { status: %w[pending], claim: "any", email: "confirmed", sort: "newest" }.freeze

    attr_reader :filters

    def initialize(scope, filters = {}, viewer: nil)
      @scope   = scope
      @viewer  = viewer
      filters  = filters.to_h.symbolize_keys
      normalise_status(filters)
      normalise_multiple(filters, :flag, :flag_match)
      normalise_multiple(filters, :watchword, :watchword_match)
      filters.delete(:severity) unless SEVERITIES.include?(filters[:severity])
      @filters = DEFAULT.merge(filters.compact_blank)
    end

    def call
      relation = @scope
      relation = relation.where(status: filters[:status]) unless filters[:status] == "all"
      relation = apply_claim(relation)
      relation = apply_email(relation)
      relation = apply_flags(relation)
      relation = apply_watchwords(relation) if filters[:watchword].present?
      relation = relation.search(filters[:search])
      apply_sort(relation).includes(:flags, :claimed_by, :instance)
    end

    def active? = filters.except(*DEFAULT.keys) != {} || filters != DEFAULT

    # Same as the plain queue landing page: pending, verified, unclaimed-or-not,
    # any moderator. Sort order doesn't count as a filter here — an empty
    # "newest" queue and an empty "riskiest" queue are the same empty queue.
    def unfiltered? = filters.except(:sort) == DEFAULT.except(:sort)

    # The chosen watchwords, looked up among the queue's own instance's only:
    # an id from elsewhere would otherwise run another instance's pattern text
    # over this queue.
    def watchwords
      @watchwords ||= available_watchwords.where(id: Array(filters[:watchword]))
    end

    # Disabled ones too: they can still be on requests they flagged earlier.
    def available_watchwords = KeywordRule.where(instance_id: @scope.select(:instance_id)).order(:pattern)

    def watchword_match = filters[:watchword_match] || "any"

    def flag_match = filters[:flag_match] || "any"

    private

    # Any of the chosen statuses. Unlike the other multiple selects, choosing
    # none is not "no filter" -- that would be the default, pending -- but any
    # status: the select keeps its hidden blank entry so an emptied one is
    # still sent. "all" is what links (and the select before it had chips) say.
    def normalise_status(filters)
      return unless filters.key?(:status)

      statuses = Array(filters[:status]).compact_blank
      filters[:status] = statuses.empty? || statuses.include?("all") ? "all" : statuses & RegistrationRequest::STATUSES
    end

    # A multiple select sends a blank entry even when nothing is chosen, and a
    # link from before it was one sends a single value. Its any/all switch is
    # sent with every submit; it only means something next to chosen values,
    # and only when it departs from the default.
    def normalise_multiple(filters, key, match_key)
      filters[key] = Array(filters[key]).compact_blank if filters.key?(key)
      filters.delete(match_key) unless filters[key].present? && filters[match_key] == "all"
    end

    # The severity applies to the chosen flags themselves; with none chosen,
    # to any flag the request carries.
    def apply_flags(relation)
      rules    = Array(filters[:flag]) & Flags.rule_names
      severity = filters[:severity]

      if filters[:flag].blank?
        severity ? relation.with_flag(nil, min_severity: severity) : relation
      elsif flag_match == "all"
        # A flag that does not exist is on no request, so none has them all.
        return relation.none if rules.size < filters[:flag].uniq.size

        rules.inject(relation) { |scope, rule| scope.with_flag(rule, min_severity: severity) }
      else
        relation.with_flag(rules, min_severity: severity)
      end
    end

    def apply_watchwords(relation)
      return relation.with_watchwords(watchwords) unless watchword_match == "all"
      # A chosen watchword that no longer exists flags nothing, so nothing
      # can have been flagged by all of them.
      return relation.none if watchwords.size < Array(filters[:watchword]).uniq.size

      watchwords.inject(relation) { |scope, rule| scope.with_watchwords([ rule ]) }
    end

    def apply_claim(relation)
      case filters[:claim]
      when "unclaimed" then relation.unclaimed
      when "mine"      then relation.claimed_by_moderator(@viewer)
      when "theirs"    then relation.claimed.where.not(claimed_by: @viewer)
      else relation
      end
    end

    def apply_email(relation)
      case filters[:email]
      when "unconfirmed" then relation.email_unconfirmed
      when "any"         then relation
      else relation.email_confirmed
      end
    end

    def apply_sort(relation)
      case filters[:sort]
      when "oldest" then relation.oldest_first
      when "risk"   then relation.riskiest_first
      else relation.newest_first
      end
    end
  end
end
