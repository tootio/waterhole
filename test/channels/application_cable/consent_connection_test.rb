require "test_helper"

class ApplicationCable::ConsentConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  test "rejects a moderator who has not consented" do
    session = sessions(:avery)
    session.moderator.update!(consented_at: nil)
    cookies.signed[:session_id] = session.id

    assert_reject_connection { connect }
  end
end
