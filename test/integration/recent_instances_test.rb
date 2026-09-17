require "test_helper"

class RecentInstancesTest < ActionDispatch::IntegrationTest
  test "the sign-in page does not disclose which instances use this Waterhole" do
    get new_session_path

    assert_response :success
    assert_no_match(/alpha\.example|beta\.example/, response.body)
    assert_select "button", text: "Forget", count: 0
  end

  test "an instance signed in to from this browser is offered after signing out" do
    sign_in_as moderators(:avery), remember: true
    delete session_path
    get new_session_path

    assert_select "li button", text: "alpha.example"
    assert_no_match(/beta\.example/, response.body, "only this browser's own history")
  end

  test "the most recent instance comes first and duplicates collapse" do
    sign_in_as moderators(:avery), remember: true
    sign_in_as moderators(:casey), remember: true
    sign_in_as moderators(:avery), remember: true
    delete session_path
    get new_session_path

    assert_equal %w[alpha.example beta.example],
      css_select("li form:first-child button").map { it.text.strip }
  end

  test "an instance can be forgotten" do
    sign_in_as moderators(:avery), remember: true
    delete session_path

    delete session_recent_instance_path, params: { domain: "alpha.example" }
    assert_redirected_to new_session_path
    follow_redirect!

    assert_no_match(/alpha\.example/, response.body)
  end

  test "a forged, unsigned cookie is ignored" do
    cookies[:recent_instances] = "evil.example"
    get new_session_path

    assert_no_match(/evil\.example/, response.body)
  end

  test "the cookie expires after 90 days" do
    freeze_time do
      sign_in_as moderators(:avery), remember: true

      header = Array(response.headers["Set-Cookie"]).join("\n").lines.find { it.start_with?("recent_instances=") }
      assert header, "sign-in should set the recent_instances cookie"
      assert_includes header, "expires=#{90.days.from_now.httpdate}"
    end
  end

  # Opt-in: the cookie is set only when "Remember this instance" is ticked.
  test "an instance is remembered only if asked" do
    sign_in_as moderators(:avery)
    delete session_path
    get new_session_path
    assert_select "li button", { count: 0, text: "alpha.example" }
  end

  test "signing in without ticking it forgets a remembered instance" do
    sign_in_as moderators(:avery), remember: true
    delete session_path
    sign_in_as moderators(:avery)
    delete session_path
    get new_session_path

    assert_select "li button", { count: 0, text: "alpha.example" }
  end

  test "the sign-in form offers the choice, unticked" do
    get new_session_path
    assert_select "input[type=checkbox][name=remember]:not([checked])"
  end
end
