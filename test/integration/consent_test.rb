require "test_helper"

class ConsentTest < ActionDispatch::IntegrationTest
  setup do
    @moderator = moderators(:avery)
    @moderator.update!(consented_at: nil, consented_privacy_digest: nil)
  end

  test "until they consent, a moderator reaches only the consent page and the legal pages" do
    sign_in_as @moderator
    get registration_requests_path(sort: "oldest")
    assert_redirected_to consent_path

    get keyword_rules_path
    assert_redirected_to consent_path

    get privacy_path
    assert_response :success

    get consent_path
    assert_response :success
    assert_select "nav a", { count: 0, text: "Queue" }
    assert_select "button", { count: 0, text: "Sync now" }
    assert_select "button", "Agree and continue"
    assert_select "button", "Decline and delete my data"
  end

  test "agreeing continues to where they were going" do
    sign_in_as @moderator
    get registration_requests_path(sort: "oldest")

    post consent_path

    assert_redirected_to registration_requests_url(sort: "oldest")
    assert @moderator.reload.consent_current?
    get root_path
    assert_response :success
  end

  test "declining signs out and deletes a moderator who left no trace" do
    sign_in_as @moderator
    @moderator.notes.delete_all
    @moderator.decisions.delete_all
    claimed = registration_requests(:claimed_alpha)
    claimed.update_columns(claimed_by_id: @moderator.id, claimed_at: Time.current)

    delete consent_path

    assert_redirected_to new_session_path
    refute Moderator.exists?(@moderator.id)
    assert_nil claimed.reload.claimed_by_id
    get root_path
    assert_redirected_to new_session_path
  end

  # notes and decisions keep pointing at the row, and both columns are NOT NULL.
  test "declining anonymises a moderator whose notes are part of the record" do
    registration_requests(:claimed_alpha).notes.create!(moderator: @moderator, body: "Looks fine.")
    instances(:alpha).update!(sync_moderator: @moderator)
    sign_in_as @moderator

    delete consent_path

    forgotten = Moderator.find(@moderator.id)
    assert_equal "former-moderator", forgotten.username
    assert_equal "forgotten-#{@moderator.id}", forgotten.mastodon_account_id
    assert_nil forgotten.access_token
    assert_nil forgotten.display_name
    assert_empty forgotten.sessions
    refute_equal @moderator.id, instances(:alpha).reload.sync_moderator_id, "sync must not keep a forgotten token"
  end

  test "a changed privacy policy asks again" do
    with_legal_documents do
      @moderator.update!(consented_at: 1.day.ago, consented_privacy_digest: LegalDocuments.privacy_digest)
      assert @moderator.consent_current?
    end

    with_legal_documents(privacy_policy: "# Privacy\n\nWe now keep a little more.\n") do
      refute @moderator.consent_current?
      sign_in_as @moderator
      get root_path
      assert_redirected_to consent_path
    end
  end

  test "sync never borrows the token of a moderator who has not consented" do
    instances(:alpha).update!(sync_moderator: nil)
    moderators(:blake).update!(consented_at: nil)

    assert_nil instances(:alpha).sync_token_holder
  end
end
