require "test_helper"
require "capybara/selenium/driver"

# Capybara 3.40 ends every Chrome session reset with
#   Storage.clearDataForOrigin(origin: "*")
# Chrome 158 rejects "*" ("invalid argument: * is not a valid URL"), so every
# system test errors in teardown. Clear cookies browser-wide instead, and
# local storage for the origin the test was on, which works on old and new
# Chrome alike. Drop this once a Capybara release stops sending "*".

module ChromeResetWithoutWildcardOrigin
  def reset!
    @origin_before_reset = origin_of_current_page if @browser
    super
  end

  private

  def execute_cdp(cmd, params = {})
    return super unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    super("Network.clearBrowserCookies")
    if @origin_before_reset && params[:storageTypes].to_s.include?("local_storage")
      super(cmd, params.merge(origin: @origin_before_reset, storageTypes: "local_storage"))
    end
  end

  def origin_of_current_page
    uri = URI(current_url)
    "#{uri.scheme}://#{uri.host}:#{uri.port}" if uri.host
  rescue StandardError
    nil
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeResetWithoutWildcardOrigin)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  # ActionDispatch::IntegrationTest#sign_in_as (test_helper.rb) drives requests
  # through its own in-process client, not the real browser Capybara/Selenium
  # is controlling here, so its session cookie never reaches that browser.
  # This visits the same dev-only endpoint for real, so the cookie lands where
  # the browser under test can actually use it.
  def sign_in_as(moderator)
    token = Rails.application.message_verifier(:dev_sign_in)
      .generate({ moderator_id: moderator.id }, expires_in: 1.hour)
    visit "/dev/sign_in?token=#{token}"
  end
end
