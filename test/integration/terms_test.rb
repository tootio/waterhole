require "test_helper"

class TermsTest < ActionDispatch::IntegrationTest
  test "the legal pages are readable signed out" do
    [ terms_path, privacy_path, imprint_path ].each do |path|
      get path
      assert_response :success
    end
  end

  test "unpublished documents render the example text behind a warning" do
    get imprint_path

    assert_response :success
    assert_select "body", /example text/i
  end

  test "the footer links the legal pages on the sign-in page" do
    get new_session_path

    assert_select "footer a[href=?]", terms_path
    assert_select "footer a[href=?]", privacy_path
    assert_select "footer a[href=?]", imprint_path
  end

  test "a moderator in the grace window keeps working and sees the deadline" do
    instance = instances(:alpha)
    instance.update!(status: "terms_outdated", verified_at: 1.day.ago,
      accepted_terms_digest: "old" * 16, terms_grace_until: 10.days.from_now)

    sign_in_as moderators(:avery)
    get root_path

    assert_response :success, "grace means the queue still works"
    assert_select "body", /needs to accept updated documents/i
  end

  # The page they are told to read must stay reachable once they are locked out,
  # or the instruction is circular.
  test "an overdue instance is signed out but can still read the terms" do
    instance = instances(:alpha)
    sign_in_as moderators(:avery)
    get root_path
    assert_response :success

    instance.update!(status: "terms_outdated", terms_grace_until: 1.hour.ago)

    get root_path
    assert_redirected_to new_session_path
    assert_match(/has not accepted the current terms/, flash[:alert])

    get terms_path
    assert_response :success
  end

  test "signing in is refused for a domain that has not accepted the terms" do
    with_legal_documents do
      DnsAllowlist.stub_resolver(dns_record) do
        post session_path, params: { domain: "newcomer.example" }
      end

      assert_response :forbidden
      assert_match(/has not accepted the current terms/, response.body)
      assert_match(/accepted_tos=#{LegalDocuments.digest}/, response.body)
    end
  end
end
