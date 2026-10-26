class StatsController < ApplicationController
  # The herd-wide chart is a sum, and with two herds in it, the sum minus your
  # own count is the other herd's count. From three up, no single herd's
  # signups can be read back out of it.
  MIN_SHARED_HERDS = 3

  def show
    @period = RegistrationStats::Series.period(params[:period])
    @series = RegistrationStats::Series.new([ current_instance ], period: @period)

    # The same reciprocity as the signals themselves: only a herd that shares
    # sees what is shared.
    return unless current_instance.participating?

    @shared_herds = Instance.participating.count
    if @shared_herds >= MIN_SHARED_HERDS
      @shared_series = RegistrationStats::Series.new(Instance.participating, period: @period)
    end
  end
end
