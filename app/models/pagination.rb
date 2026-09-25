# Offset pagination for the queue and the sync history.
#
# Deliberately hand-rolled and tiny: a pending-registration queue is tens to low
# hundreds of rows, so this never needs to be clever, and it keeps a dependency
# with a fast-moving API out of the request path.
#
# The sync history pages classically (`records`: page N alone). The queue loads
# more instead, so there `page` means "everything through page N"
# (`through_records`), and `records_from` is the slice a "Load more" appends.
class Pagination
  attr_reader :page, :per_page, :total

  def initialize(scope, page:, per_page: 25)
    @per_page = per_page.clamp(1, 100)
    @total    = scope.limit(nil).offset(nil).count
    @page     = [ page.to_i, 1 ].max
    @page     = pages if pages.positive? && @page > pages
    @scope    = scope
  end

  def records = records_from(page)

  def through_records = records_from(1)

  # Pages `from` through `page`, for appending to what is already on screen.
  def records_from(from)
    from = from.to_i.clamp(1, page)
    @scope.limit((page - from + 1) * per_page).offset((from - 1) * per_page)
  end

  def shown = [ page * per_page, total ].min

  def pages = (total.to_f / per_page).ceil

  def prev = page > 1 ? page - 1 : nil

  def next = page < pages ? page + 1 : nil

  def many? = pages > 1
end
