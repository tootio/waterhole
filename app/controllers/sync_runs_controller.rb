class SyncRunsController < ApplicationController
  def index
    @sync_runs = current_instance.sync_runs.recent.limit(50)
  end
end
