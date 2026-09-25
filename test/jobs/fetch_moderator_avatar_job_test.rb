require "test_helper"

class FetchModeratorAvatarJobTest < ActiveJob::TestCase
  PNG = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b
  URL = "https://files.example/a.png".freeze

  setup do
    @moderator = moderators(:avery)
    @moderator.update!(avatar_url: URL)
  end

  test "stores the image and the type its bytes say it is" do
    stub_request(:get, URL).to_return(status: 200, body: PNG, headers: { "Content-Type" => "image/svg+xml" })

    FetchModeratorAvatarJob.perform_now(@moderator)

    avatar = @moderator.reload.avatar
    assert_equal PNG, avatar.image
    assert_equal "image/png", avatar.content_type
    assert_equal URL, avatar.source_url
  end

  test "a rejected image leaves no avatar where the URL changed" do
    @moderator.create_avatar!(image: PNG, content_type: "image/png", source_url: "https://files.example/old.png")
    stub_request(:get, URL).to_return(status: 200, body: "<svg/>")

    FetchModeratorAvatarJob.perform_now(@moderator)

    assert_nil @moderator.reload.avatar
  end

  test "a failed refetch of the same URL keeps the copy we have" do
    @moderator.create_avatar!(image: PNG, content_type: "image/png", source_url: URL)
    stub_request(:get, URL).to_timeout

    FetchModeratorAvatarJob.perform_now(@moderator)

    assert_equal PNG, @moderator.reload.avatar.image
  end

  test "no avatar URL, no avatar" do
    @moderator.create_avatar!(image: PNG, content_type: "image/png", source_url: URL)
    @moderator.update!(avatar_url: nil)

    FetchModeratorAvatarJob.perform_now(@moderator)

    assert_nil @moderator.reload.avatar
  end

  # The consent page is where they agree to us keeping it.
  test "nothing is copied before consent" do
    @moderator.update!(consented_at: nil)

    FetchModeratorAvatarJob.perform_now(@moderator)

    assert_nil @moderator.reload.avatar
    assert_not_requested :get, URL
  end
end
