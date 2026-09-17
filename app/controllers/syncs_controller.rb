class SyncsController < ApplicationController
  # Per instance, not per person: a whole team pressing Sync still costs the
  # instance's API budget once per run. The schedule syncs every 5 minutes anyway.
  throttle to: 5, within: 10.minutes, name: "sync", by: -> { current_instance.id }

  def create
    SyncInstanceJob.perform_later(current_instance)
    redirect_back_or_to root_path, notice: "Syncing #{current_instance.domain} in the background."
  end
end
