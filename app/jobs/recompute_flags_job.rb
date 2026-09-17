class RecomputeFlagsJob < ApplicationJob
  queue_as :default

  def perform(request)
    request.recompute_flags!
  end
end
