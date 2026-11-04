require "test_helper"

class PushNotificationsTest < ActionDispatch::IntegrationTest
  include PushTestHelper

  setup do
    @moderator = sign_in_as(moderators(:avery))
    @endpoint = "#{PushTestHelper::FCM}this-browser"
  end

  def subscription_params(endpoint = @endpoint) = { push_subscription: { endpoint:, **browser_keys }, time_zone: "Europe/Berlin" }

  def endpoint_params(endpoint = @endpoint) = { push_subscription: { endpoint: } }

  test "the settings page needs a signed-in moderator" do
    delete session_path
    get push_preferences_path
    assert_redirected_to new_session_path
  end

  test "the settings page offers the choices, and opens opting in to nothing" do
    get push_preferences_path

    assert_response :success
    assert_select "select[name=?]", "push_preference[new_frequency]"
    assert_select "input[type=time][name=?]", "push_preference[daily_time]"
    assert_select "a[href=?]", push_help_path
    assert_equal 0, PushPreference.where(moderator: @moderator).count
    assert_select "#account-menu a[href=?]", push_preferences_path
    assert_select "link[rel=manifest][href=?]", pwa_manifest_path
  end

  test "saving settings, including the chosen daily time" do
    patch push_preferences_path, params: { push_preference: {
      new_frequency: "daily", new_scope: "all_pending", daily_time: "18:15",
      forgotten_after_days: "7", forgotten_scope: "awaiting", time_zone: "Europe/Berlin"
    } }

    assert_redirected_to push_preferences_path
    preference = @moderator.reload.push_preference
    assert preference.new_daily?
    assert preference.new_all_pending?
    assert_equal "18:15", preference.daily_time
    assert_equal 7, preference.forgotten_after_days
    assert_equal "Europe/Berlin", preference.time_zone
  end

  test "bad settings come back with an error" do
    patch push_preferences_path, params: { push_preference: {
      new_frequency: "constantly", new_scope: "awaiting", daily_time: "18:15",
      forgotten_after_days: "", forgotten_scope: "awaiting", time_zone: "UTC"
    } }

    assert_response :unprocessable_entity
    assert_select ".bg-red-50"
  end

  test "an impossible daily time comes back with an error" do
    [ "", "soon", "12:60" ].each do |daily_time|
      patch push_preferences_path, params: { push_preference: { daily_time: } }
      assert_response :unprocessable_entity
    end
  end

  test "a null time zone is UTC, not a database error" do
    patch push_preferences_path, params: { push_preference: { time_zone: nil } }, as: :json
    assert_equal "UTC", @moderator.reload.push_preference.time_zone
  end

  test "enabling a browser opts in and starts counting from now" do
    preference = travel_to(30.days.ago) { PushPreference.create!(moderator: @moderator) }

    freeze_time
    post push_subscriptions_path, params: subscription_params, as: :json

    assert_response :created
    assert_equal 1, @moderator.push_subscriptions.count
    assert_equal Time.current, preference.reload.new_checked_at
    assert_equal "Europe/Berlin", preference.time_zone
  end

  test "enabling the first browser creates default settings, with reminders off" do
    post push_subscriptions_path, params: subscription_params, as: :json

    preference = @moderator.reload.push_preference
    assert preference.new_hourly?
    refute preference.forgotten_on?
  end

  test "a second browser does not reset the count, and enabling twice stays one row" do
    subscribe_browser(@moderator)
    preference = travel_to(1.hour.ago) { PushPreference.create!(moderator: @moderator) }

    assert_no_changes -> { preference.reload.new_checked_at } do
      2.times { post push_subscriptions_path, params: subscription_params, as: :json }
    end
    assert_equal 2, @moderator.push_subscriptions.count
  end

  test "only the first browser sets the time zone" do
    subscribe_browser(@moderator)
    preference = PushPreference.create!(moderator: @moderator, time_zone: "Asia/Tokyo")

    post push_subscriptions_path, params: subscription_params, as: :json

    assert_equal "Asia/Tokyo", preference.reload.time_zone
  end

  test "keys that cannot encrypt are refused" do
    post push_subscriptions_path, params: { push_subscription: { endpoint: @endpoint, p256dh: "nope", auth: "nope" } }, as: :json

    assert_response :unprocessable_entity
    assert_equal 0, @moderator.push_subscriptions.count
  end

  test "an endpoint that is not a push service is refused" do
    post push_subscriptions_path, params: subscription_params("https://169.254.169.254/latest"), as: :json

    assert_response :unprocessable_entity
    assert_equal 0, @moderator.push_subscriptions.count
    assert_nil @moderator.reload.push_preference
  end

  test "check is about this moderator: a shared browser is not enabled for the next person" do
    subscribe_browser(moderators(:blake), endpoint: @endpoint)

    post check_push_subscriptions_path, params: endpoint_params, as: :json
    assert_equal({ "enabled" => false, "in_use" => true }, response.parsed_body)

    subscribe_browser(@moderator, endpoint: @endpoint)
    post check_push_subscriptions_path, params: endpoint_params, as: :json
    assert_equal({ "enabled" => true, "in_use" => true }, response.parsed_body)
  end

  test "check says when nobody uses this browser's subscription" do
    post check_push_subscriptions_path, params: endpoint_params, as: :json
    assert_equal({ "enabled" => false, "in_use" => false }, response.parsed_body)
  end

  test "turning off says whether someone else still uses this browser" do
    subscribe_browser(@moderator, endpoint: @endpoint)
    subscribe_browser(moderators(:blake), endpoint: @endpoint)

    delete current_push_subscriptions_path, params: endpoint_params, as: :json
    assert_equal({ "in_use" => true }, response.parsed_body)

    moderators(:blake).push_subscriptions.destroy_all
    delete current_push_subscriptions_path, params: endpoint_params, as: :json
    assert_equal({ "in_use" => false }, response.parsed_body)
  end

  test "a signed-out request is redirected, which the page refuses to follow" do
    delete session_path
    post send_test_push_subscriptions_path, params: endpoint_params, as: :json
    assert_response :redirect
  end

  test "a test goes to this browser only" do
    this = subscribe_browser(@moderator, endpoint: @endpoint)
    other = subscribe_browser(@moderator)
    stub_request(:post, this.endpoint).to_return(status: 201)

    post send_test_push_subscriptions_path, params: endpoint_params, as: :json

    assert_response :ok
    assert_requested :post, this.endpoint, times: 1
    assert_not_requested :post, other.endpoint
  end

  test "a test reports what happened" do
    subscribe_browser(@moderator, endpoint: @endpoint)
    stub_request(:post, @endpoint).to_return(status: 503)
    post send_test_push_subscriptions_path, params: endpoint_params, as: :json
    assert_response :bad_gateway

    stub_request(:post, @endpoint).to_return(status: 410)
    post send_test_push_subscriptions_path, params: endpoint_params, as: :json
    assert_response :gone
    assert_equal 0, @moderator.push_subscriptions.count
  end

  test "a moderator cannot test or remove another moderator's browser" do
    theirs = subscribe_browser(moderators(:blake), endpoint: @endpoint)

    post send_test_push_subscriptions_path, params: endpoint_params, as: :json
    assert_response :not_found
    assert_not_requested :post, @endpoint

    delete current_push_subscriptions_path, params: endpoint_params, as: :json
    assert PushSubscription.exists?(theirs.id)

    delete push_subscription_path(theirs)
    assert_response :not_found
    assert PushSubscription.exists?(theirs.id)
  end

  test "test notifications are throttled" do
    subscribe_browser(@moderator, endpoint: @endpoint)
    stub_request(:post, @endpoint).to_return(status: 201)

    5.times { post send_test_push_subscriptions_path, params: endpoint_params, as: :json }
    assert_response :ok

    post send_test_push_subscriptions_path, params: endpoint_params, as: :json
    assert_response :too_many_requests
  end

  test "turning off this browser and removing one from the list" do
    this = subscribe_browser(@moderator, endpoint: @endpoint)
    listed = subscribe_browser(@moderator)

    get push_preferences_path
    assert_select "form[action=?]", push_subscription_path(listed)
    assert_match(/Through Google/, response.body)

    delete current_push_subscriptions_path, params: endpoint_params, as: :json
    assert_response :ok
    refute PushSubscription.exists?(this.id)

    delete push_subscription_path(listed)
    assert_redirected_to push_preferences_path
    refute PushSubscription.exists?(listed.id)
  end

  test "subscription secrets stay out of the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("push_subscription" => { "endpoint" => "e", "p256dh" => "p", "auth" => "a" }, "authorized" => "keep")

    assert_equal({ "endpoint" => "[FILTERED]", "p256dh" => "[FILTERED]", "auth" => "[FILTERED]" }, filtered["push_subscription"])
    assert_equal "keep", filtered["authorized"]
  end

  test "the help page explains the hoops" do
    get push_help_path

    assert_response :success
    assert_match(/Add to Home Screen/, response.body)
    assert_match(/Apple, Google, Mozilla or Microsoft/, response.body)
  end

  test "the worker and manifest are public, and the worker can take scope /" do
    delete session_path

    get "/service-worker.js"
    assert_response :success
    assert_match(/javascript/, response.media_type)
    assert_match(/addEventListener\("push"/, response.body)

    get pwa_manifest_path(format: :json)
    assert_response :success
    assert_equal "standalone", response.parsed_body["display"]
    assert_equal "/", response.parsed_body["scope"]
  end

  test "the linked manifest and the worker answer whatever the client accepts" do
    [ "text/html", "*/*", nil ].each do |accept|
      [ pwa_manifest_path, pwa_service_worker_path ].each do |path|
        get path, headers: { "Accept" => accept }
        assert_response :success, "#{path} with Accept: #{accept.inspect}"
      end
    end
  end

  test "the consent page says what push stores, only where push exists" do
    @moderator.update!(consented_at: nil)

    get consent_path
    assert_select "li", text: /Only if you use push notifications/

    without_vapid do
      get consent_path
      assert_select "li", text: /push notifications/, count: 0
    end
  end

  test "without VAPID keys the feature does not exist" do
    without_vapid do
      get root_path
      assert_select "link[rel=manifest]", false
      assert_select "#account-menu", text: /Notifications/, count: 0

      [ "/notifications", "/help/push", "/manifest.json", "/service-worker.js" ].each do |path|
        get path
        assert_response :not_found, "#{path} should not exist"
      end
    end
  end
end
