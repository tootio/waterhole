require "test_helper"

class ReauthorizeBannerTest < ActionDispatch::IntegrationTest
  setup { @moderator = moderators(:avery) }

  test "a moderator whose token predates the search scope is told what their next sign-in will ask" do
    @moderator.update!(token_scopes: "profile admin:read:accounts admin:write:accounts")
    sign_in_as @moderator

    get registration_requests_path

    assert_select "a[href=?]", sign_in_help_path(anchor: "authorize-again")
    assert_match(/authorize Waterhole again/, response.body)
  end

  test "it is gone once they have signed in with it" do
    @moderator.update!(token_scopes: Mastodon::OAuth::MODERN_SCOPES)
    sign_in_as @moderator

    get registration_requests_path

    assert_no_match(/authorize Waterhole again/, response.body)
  end

  test "the sign-in help page is public" do
    get sign_in_help_path

    assert_response :success
    %w[authorize-again declined listed-twice could-not-prove no-instance-actor].each { assert_select "section##{it}" }
    assert_select "#listed-twice a[href*='authorized_applications']", count: 0
  end

  test "signed in, the help page links to the moderator's own authorized apps" do
    sign_in_as @moderator

    get sign_in_help_path

    assert_select "#listed-twice a[href=?]", "https://alpha.example/oauth/authorized_applications",
      text: "Preferences → Account → Authorized apps"
  end
end
