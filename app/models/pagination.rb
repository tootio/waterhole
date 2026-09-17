# Offset pagination for the queue.
#
# Deliberately hand-rolled and tiny: a pending-registration queue is tens to low
# hundreds of rows, so this never needs to be clever, and it keeps a dependency
# with a fast-moving API out of the request path.
class Pagination
  attr_reader :page, :per_page, :total

  def initialize(scope, page:, per_page: 25)
    @per_page = per_page.clamp(1, 100)
    @total    = scope.limit(nil).offset(nil).count
    @page     = [ page.to_i, 1 ].max
    @page     = pages if pages.positive? && @page > pages
    @scope    = scope
  end

  def records = @scope.limit(per_page).offset((page - 1) * per_page)

  def pages = (total.to_f / per_page).ceil

  def prev = page > 1 ? page - 1 : nil

  def next = page < pages ? page + 1 : nil

  def many? = pages > 1
end
