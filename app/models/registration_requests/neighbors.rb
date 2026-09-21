module RegistrationRequests
  # Finds the record immediately before/after a given one within an already
  # filtered-and-sorted relation, keyed by id rather than a page number, so a
  # queue that grows or shrinks while a moderator works it doesn't skip or
  # repeat a row. Looked up fresh on every navigation for the same reason,
  # rather than being computed once and carried on the page.
  class Neighbors
    def initialize(relation, current)
      @relation = relation
      @current  = current
    end

    def in_list? = @relation.exists?(id: @current.id)

    def before = neighbor(-1)
    def after  = neighbor(1)

    private

    def neighbor(offset)
      index = ordered_ids.index(@current.id)
      return nil unless index

      target = index + offset
      ordered_ids[target] if target >= 0
    end

    # id as a secondary sort key, after whatever order the caller already
    # applied, so ties (e.g. two signups in the same second) land in a fixed
    # order instead of shuffling between the page render and this lookup.
    # unscope(:includes): the caller's relation eager-loads associations for
    # rendering, which pluck doesn't need -- and keeping it forces a JOIN
    # whenever a filter's raw SQL (e.g. the search scope) mentions a column
    # name shared with a joined table, tripping Postgres over the ambiguity.
    def ordered_ids
      @ordered_ids ||= @relation.unscope(:includes).order(:id).pluck(:id)
    end
  end
end
