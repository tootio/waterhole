require "test_helper"

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
