require "application_system_test_case"

# The real page, controller, CSP and Trusted Types, with only the browser's push
# service replaced: headless Chrome has none to talk to.
class PushNotificationsSystemTest < ApplicationSystemTestCase
  include PushTestHelper

  ENDPOINT = "#{FCM}system-test".freeze

  setup do
    @moderator = moderators(:avery)
    sign_in_as @moderator
  end

  # Stands in for navigator.serviceWorker and Notification. register() still gets
  # what the page really passes, so the Trusted Types policy is exercised on it.
  def fake_push_api(result: "granted")
    page.execute_script(<<~JS, ENDPOINT, browser_keys[:p256dh], browser_keys[:auth], result)
      const [ endpoint, p256dh, auth, result ] = arguments
      let subscription = null
      const pushManager = {
        getSubscription: async () => subscription,
        subscribe: async () => subscription = {
          endpoint,
          toJSON: () => ({ endpoint, keys: { p256dh, auth } }),
          unsubscribe: async () => { subscription = null; return true }
        }
      }
      const registration = { pushManager }
      window.registeredWorker = null
      Object.defineProperty(navigator, "serviceWorker", { configurable: true, value: {
        ready: Promise.resolve(registration),
        getRegistration: async () => window.registeredWorker && registration,
        register: async url => { window.registeredWorker = url; window.registeredWorkerType = url.constructor.name; return registration }
      } })
      window.PushManager ??= function () {}
      window.Notification = { permission: "default", requestPermission: async () => { window.Notification.permission = result; return result } }
    JS
  end

  test "enable, test and disable in this browser" do
    visit push_preferences_path
    assert_text "Notifications are off in this browser."
    assert_equal 0, @moderator.push_subscriptions.count, "merely visiting must not subscribe"

    fake_push_api
    click_on "Turn on in this browser"
    assert_text "Notifications are on in this browser."

    assert_equal "TrustedScriptURL", page.evaluate_script("window.registeredWorkerType")
    assert_equal "/service-worker.js", page.evaluate_script("String(window.registeredWorker)")
    assert_equal [ ENDPOINT ], @moderator.push_subscriptions.map(&:endpoint)
    assert_equal page.evaluate_script("Intl.DateTimeFormat().resolvedOptions().timeZone"), @moderator.reload.push_preference.time_zone

    stub_request(:post, ENDPOINT).to_return(status: 201)
    click_on "Send a test notification"
    assert_text "Test notification sent."
    assert_requested :post, ENDPOINT, times: 1

    click_on "Turn off in this browser"
    assert_text "Notifications are off in this browser."
    assert_equal 0, @moderator.push_subscriptions.count
  end

  test "saving the settings keeps this browser's section working" do
    visit push_preferences_path
    assert_text "Notifications are off in this browser."
    fake_push_api
    click_on "Turn on in this browser"
    assert_text "Notifications are on in this browser."

    click_on "Save"
    assert_text "Notification settings saved."

    assert_text "Notifications are on in this browser."
    assert_button "Send a test notification"
    assert_no_text "needs JavaScript"
  end

  test "someone else sharing this browser keeps its subscription when one turns off" do
    visit push_preferences_path
    assert_text "Notifications are off in this browser."
    fake_push_api
    click_on "Turn on in this browser"
    assert_text "Notifications are on in this browser."
    subscribe_browser(moderators(:blake), endpoint: ENDPOINT)
    page.execute_script(<<~JS)
      navigator.serviceWorker.getRegistration("/").then(registration => registration.pushManager.getSubscription()).then(subscription => {
        const unsubscribe = subscription.unsubscribe
        subscription.unsubscribe = async () => { sessionStorage.setItem("unsubscribed", "yes"); return unsubscribe() }
      })
    JS

    click_on "Turn off in this browser"
    assert_text "Notifications are off in this browser."

    assert_nil page.evaluate_script(%(sessionStorage.getItem("unsubscribed")))
    assert_equal 0, @moderator.push_subscriptions.count
    assert_equal 1, moderators(:blake).push_subscriptions.count
  end

  test "an expired session never reads as a test sent" do
    visit push_preferences_path
    assert_text "Notifications are off in this browser."
    fake_push_api
    click_on "Turn on in this browser"
    assert_text "Notifications are on in this browser."

    Session.where(moderator: @moderator).delete_all
    click_on "Send a test notification"

    assert_text "you may need to sign in again"
    assert_no_text "Test notification sent"
  end

  test "a subscription the push service ended is replaced, not saved again" do
    visit push_preferences_path
    assert_text "Notifications are off in this browser."
    fake_push_api
    click_on "Turn on in this browser"
    assert_text "Notifications are on in this browser."

    stub_request(:post, ENDPOINT).to_return(status: 410)
    click_on "Send a test notification"
    assert_text "has ended"

    assert_nil page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      navigator.serviceWorker.getRegistration("/").then(registration => registration.pushManager.getSubscription()).then(done)
    JS
  end

  test "declining the browser's permission enables nothing" do
    visit push_preferences_path
    assert_text "Notifications are off in this browser."

    fake_push_api(result: "denied")
    click_on "Turn on in this browser"

    assert_text "Notifications are blocked for this site."
    assert_no_button "Turn on in this browser"
    assert_equal 0, @moderator.push_subscriptions.count
  end

  test "the form saves the chosen times in the browser's zone" do
    # A zone no test browser is in, so the page has to say it will change.
    PushPreference.create!(moderator: @moderator, time_zone: "Pacific/Chatham")
    visit push_preferences_path
    browser_zone = page.evaluate_script("Intl.DateTimeFormat().resolvedOptions().timeZone")
    [ "#push_notify_window_hint", "#push_daily_time_hint" ].each do |hint|
      assert_selector hint, text: "Pacific/Chatham, or #{browser_zone} once you save"
    end

    select "Once a day", from: "Tell me"
    fill_in "Only from", with: Time.utc(2000, 1, 1, 14, 0)
    fill_in "Until", with: Time.utc(2000, 1, 1, 4, 0)
    fill_in "Daily notifications arrive around", with: Time.utc(2000, 1, 1, 18, 15)
    click_on "Save"

    assert_text "Notification settings saved."
    preference = @moderator.reload.push_preference
    assert preference.new_daily?
    assert_equal [ "14:00", "04:00", "18:15" ], [ preference.notify_from_time, preference.notify_until_time, preference.daily_time ]
    assert_equal browser_zone, preference.time_zone
  end

  test "the page registers the real worker under the real CSP" do
    visit push_preferences_path
    assert_text "Notifications are off in this browser."

    registered = page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      const policy = window.trustedTypes.createPolicy("push-service-worker", { createScriptURL: url => url })
      navigator.serviceWorker.register(policy.createScriptURL("/service-worker.js"), { scope: "/" })
        .then(registration => navigator.serviceWorker.ready.then(() => registration.unregister()))
        .then(() => done("registered"), error => done(String(error)))
    JS

    assert_equal "registered", registered
  end
end
