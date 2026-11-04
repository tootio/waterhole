# A moderator's own notification settings. Enabling a browser happens next to
# them, in push_subscription_controller.js, since only the browser can do that.
class PushPreferencesController < ApplicationController
  before_action :set_preference
  before_action :set_subscriptions

  def show
  end

  def update
    if @preference.update(preference_params)
      redirect_to push_preferences_path, notice: "Notification settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_preference
    @preference = PushPreference.for(current_moderator)
  end

  def set_subscriptions
    @subscriptions = current_moderator.push_subscriptions.order(:created_at)
  end

  def preference_params
    params.expect(push_preference: %i[new_frequency new_scope daily_time forgotten_after_days forgotten_scope time_zone])
  end
end
