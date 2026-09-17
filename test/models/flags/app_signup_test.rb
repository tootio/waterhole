require "test_helper"

class Flags::AppSignupTest < ActiveSupport::TestCase
  setup { @request = registration_requests(:pending_alpha) }

  test "an account created through an app is noted, as info" do
    @request.update!(created_by_application_id: "4711")
    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "app_signup")
    assert_equal "info", flag.severity
    assert_equal "4711", flag.details["application_id"]
  end

  test "a sign-up through the website raises nothing" do
    @request.update!(created_by_application_id: nil)
    @request.recompute_flags!

    assert_nil @request.reload.flags.find_by(rule: "app_signup")
  end
end
