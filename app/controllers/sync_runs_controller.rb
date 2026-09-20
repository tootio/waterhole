class SyncRunsController < ApplicationController
  # The page is one compact row per run, and the point of coming here is to
  # scan for the one that went wrong.
  PER_PAGE = 50

  helper_method :sync_runs_page_path

  def index
    @status = filter_params[:status]
    runs = current_instance.sync_runs.with_status(@status).recent
    @pagination = Pagination.new(runs, page: params[:page], per_page: PER_PAGE)
    @sync_runs = @pagination.records
  end

  private

  # Paging must not drop the filter, or page two of "failed" is page two of
  # everything.
  def sync_runs_page_path(page) = sync_runs_path(filter_params.merge(page:))

  def filter_params = params.permit(:status).to_h
end
