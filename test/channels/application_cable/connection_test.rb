require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  setup { @session = sessions(:avery) }

  test "connects with a live session" do
    cookies.signed[:session_id] = @session.id
    connect

    assert_equal @session.id, connection.session_id
  end

  test "rejects a connection without a session" do
    assert_reject_connection { connect }
  end

  test "rejects an expired session" do
    @session.update_column(:last_active_at, (Session::IDLE_TIMEOUT + 1.minute).ago)
    cookies.signed[:session_id] = @session.id

    assert_reject_connection { connect }
  end

  test "rejects a session whose instance is no longer admitted" do
    @session.instance.update_column(:status, "revoked")
    cookies.signed[:session_id] = @session.id

    assert_reject_connection { connect }
  end
end
