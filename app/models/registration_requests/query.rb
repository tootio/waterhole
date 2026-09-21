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
    DEFAULT = { status: "pending", claim: "any", email: "confirmed", sort: "newest" }.freeze

    attr_reader :filters

    def initialize(scope, filters = {}, viewer: nil)
      @scope   = scope
      @viewer  = viewer
      @filters = DEFAULT.merge(filters.to_h.symbolize_keys.compact_blank)
    end

    def call
      relation = @scope
      relation = relation.where(status: filters[:status]) unless filters[:status] == "all"
      relation = apply_claim(relation)
      relation = apply_email(relation)
      relation = relation.with_flag(filters[:flag]) if filters[:flag].present?
      relation = relation.search(filters[:search])
      apply_sort(relation).includes(:flags, :claimed_by, :instance)
    end

    def active? = filters.except(*DEFAULT.keys) != {} || filters != DEFAULT

    # Same as the plain queue landing page: pending, verified, unclaimed-or-not,
    # any moderator. Sort order doesn't count as a filter here — an empty
    # "newest" queue and an empty "riskiest" queue are the same empty queue.
    def unfiltered? = filters.except(:sort) == DEFAULT.except(:sort)

    private

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
