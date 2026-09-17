require "test_helper"

class VerifyModeratorJobTest < ActiveJob::TestCase
  setup do
    @moderator = moderators(:avery)
    @url = "#{@moderator.instance.base_url}/api/v1/accounts/verify_credentials"
  end

  def stub_credentials(status: 200, role: { "name" => "Moderator", "permissions" => (1 << 10).to_s })
    stub_request(:get, @url).to_return(status:,
      body: { "id" => @moderator.mastodon_account_id, "username" => "avery", "role" => role }.to_json,
      headers: { "Content-Type" => "application/json" })
  end

  test "a moderator who still has the role keeps their sessions" do
    stub_credentials

    VerifyModeratorJob.perform_now(@moderator)

    assert @moderator.reload.token_usable?
    assert_equal "Moderator", @moderator.role_name
    assert @moderator.sessions.exists?
  end

  test "a demoted moderator loses their sessions and their token" do
    stub_credentials(role: { "name" => "", "permissions" => (1 << 16).to_s })

    VerifyModeratorJob.perform_now(@moderator)

    refute @moderator.reload.token_usable?
    assert_empty @moderator.sessions
  end

  test "a token revoked in Mastodon ends the sessions" do
    stub_credentials(status: 401)

    VerifyModeratorJob.perform_now(@moderator)

    refute @moderator.reload.token_usable?
    assert_empty @moderator.sessions
  end

  test "an outage locks nobody out" do
    stub_request(:get, @url).to_timeout

    VerifyModeratorJob.perform_now(@moderator)

    assert @moderator.reload.token_usable?
    assert @moderator.sessions.exists?
  end

  test "the sweep ends expired sessions and re-checks every usable token" do
    expired = sessions(:avery)
    expired.update_column(:last_active_at, (Session::IDLE_TIMEOUT + 1.minute).ago)

    assert_enqueued_jobs Moderator.token_usable.joins(:instance).merge(Instance.syncable).count,
      only: VerifyModeratorJob do
      VerifyModeratorsJob.perform_now
    end
    refute Session.exists?(expired.id)
  end
end
