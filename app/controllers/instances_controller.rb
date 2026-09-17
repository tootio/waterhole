class InstancesController < ApplicationController
  before_action :set_instance, only: :show

  def index
    @instances = Instance.order(:domain)
  end

  def show
    @sync_runs = @instance.sync_runs.recent.limit(10)
  end

  private

  # A moderator can only inspect their own instance.
  def set_instance
    @instance = current_instance
  end
end
