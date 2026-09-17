require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  def policy = response.headers["Content-Security-Policy"].to_s

  test "pages allow only their own scripts, and inline ones by nonce" do
    sign_in_as moderators(:avery)
    get root_path

    assert_match(/default-src 'none'/, policy)
    assert_match(/script-src 'self' 'nonce-[^']+'/, policy)
    assert_match(/form-action 'self'(;|\z)/, policy)
    assert_match(/frame-ancestors 'none'/, policy)
    refute_match(/unsafe-inline|unsafe-eval/, policy)

    nonce = policy[/'nonce-([^']+)'/, 1]
    assert_select "script[type=importmap][nonce=?]", nonce
  end

  # Signing in redirects to the moderator's Mastodon server, and browsers apply
  # form-action to that redirect.
  test "only the sign-in pages may submit forms to another host" do
    get new_session_path

    assert_match(/form-action 'self' https:/, policy)
    assert_select "form[action=?][data-turbo=false]", session_path
    assert_select "meta[name=turbo-visit-control][content=reload]"
  end
end
