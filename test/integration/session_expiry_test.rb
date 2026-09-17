require "test_helper"

class SessionExpiryTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as moderators(:avery)
    @session = moderators(:avery).sessions.order(:created_at).last
  end

  test "the cookie expires with the session rather than lasting for years" do
    cookie = Array(response.headers["set-cookie"]).flat_map { it.split("\n") }.grep(/\Asession_id=/).first
    expires = Time.httpdate(cookie[/expires=([^;]+)/i, 1])

    assert_in_delta Session::IDLE_TIMEOUT.from_now, expires, 1.minute
  end

  test "a session idle for too long is ended" do
    @session.update_column(:last_active_at, (Session::IDLE_TIMEOUT + 1.minute).ago)

    get root_path

    assert_redirected_to new_session_path
    refute Session.exists?(@session.id)
  end

  test "a session past its absolute lifetime is ended even if it was active" do
    @session.update_columns(created_at: (Session::ABSOLUTE_LIFETIME + 1.minute).ago, last_active_at: Time.current)

    get root_path

    assert_redirected_to new_session_path
    refute Session.exists?(@session.id)
  end

  test "activity keeps a session alive, without a write on every request" do
    @session.update_column(:last_active_at, 1.hour.ago)
    get root_path
    assert_response :success
    touched = @session.reload.last_active_at
    assert_in_delta Time.current, touched, 5.seconds

    get root_path
    assert_equal touched, @session.reload.last_active_at
  end

  test "signing out resets the Rails session too" do
    before = session.id.to_s
    delete session_path

    refute Session.exists?(@session.id)
    refute_equal before, session.id.to_s
  end
end
