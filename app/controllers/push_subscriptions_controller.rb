# The browsers a moderator enabled. Mostly called by push_subscription_controller.js,
# which is the only thing that knows which browser this is.
class PushSubscriptionsController < ApplicationController
  # Each test posts to a third party on this request.
  throttle to: 5, within: 1.minute, name: "push_test",
    by: -> { current_moderator.id }, only: :send_test
  throttle to: 30, within: 1.minute, name: "push_subscription",
    by: -> { current_moderator.id }, only: %i[create check destroy current]

  def create
    attributes = params.expect(push_subscription: %i[endpoint p256dh auth])
    # Before find_or_initialize_by, which adds the new one to the association.
    first_browser = subscriptions.none?
    subscription = subscriptions.find_or_initialize_by(endpoint: attributes[:endpoint])
    subscription.assign_attributes(attributes)
    preference = PushPreference.for(current_moderator)
    if first_browser
      preference.time_zone = params[:time_zone] if params[:time_zone].present?
      preference.rearm
    end

    return render json: { error: "This browser's subscription is not one we can use." }, status: :unprocessable_entity unless subscription.valid?

    PushSubscription.transaction do
      preference.save!
      subscription.save!
    end
    head :created
  rescue ActiveRecord::RecordNotUnique
    # A double click: the other request saved the same thing.
    head :created
  end

  # Whether this browser is enabled for this moderator: a browser that already has
  # a subscription may have got it for someone else who shares it. Unused by anyone,
  # it is one the push service may have ended, and not worth subscribing with again.
  def check
    render json: { enabled: subscriptions.exists?(endpoint: endpoint_param), in_use: endpoint_in_use? }
  end

  # Straight from this request, so the moderator learns the outcome right away.
  def send_test
    subscription = subscriptions.find_by!(endpoint: endpoint_param)

    status = case PushNotifications::Sender.deliver_to(subscription, PushNotifications::Message.test)
    when :delivered then :ok
    when :gone then :gone
    else :bad_gateway
    end
    head status
  end

  # This browser, turned off from the browser itself. Unsubscribing it is only
  # safe if nobody else who shares it is still using it.
  def current
    subscriptions.find_by(endpoint: endpoint_param)&.destroy!
    render json: { in_use: endpoint_in_use? }
  end

  # Any browser, from the list on the settings page.
  def destroy
    subscriptions.find(params[:id]).destroy!
    redirect_to push_preferences_path, notice: "Browser removed."
  end

  private

  def subscriptions = current_moderator.push_subscriptions

  def endpoint_in_use? = PushSubscription.exists?(endpoint: endpoint_param)

  def endpoint_param = params.expect(push_subscription: [ :endpoint ])[:endpoint]
end
