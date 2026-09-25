require "test_helper"

class AvatarTest < ActionDispatch::IntegrationTest
  PNG = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b

  test "serves the moderator's own copy, locked down" do
    moderator = sign_in_as moderators(:avery)
    moderator.create_avatar!(image: PNG, content_type: "image/png", source_url: "https://files.example/a.png")

    get avatar_path(v: moderator.avatar_version)

    assert_response :success
    assert_equal PNG, response.body.b
    assert_equal "image/png", response.media_type
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "default-src 'none'; sandbox", response.headers["Content-Security-Policy"]
    assert_match(/private/, response.headers["Cache-Control"])
    assert_match(/inline/, response.headers["Content-Disposition"])
  end

  test "no copy, no avatar" do
    sign_in_as moderators(:avery)

    get avatar_path

    assert_response :not_found
  end

  test "only for someone signed in" do
    get avatar_path

    assert_redirected_to new_session_path
  end

  # The account menu, and so the avatar, is on the consent page too.
  test "is served before consent" do
    moderator = sign_in_as moderators(:avery)
    moderator.create_avatar!(image: PNG, content_type: "image/png", source_url: "https://files.example/a.png")
    moderator.update!(consented_at: nil)

    get avatar_path

    assert_response :success
  end
end
