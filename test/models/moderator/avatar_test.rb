require "test_helper"

class Moderator::AvatarTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PNG = "\x89PNG\r\n\x1A\n".b

  setup { @moderator = moderators(:avery) }

  test "a new avatar URL is copied in the background" do
    @moderator.update!(avatar_url: "https://files.example/new.png")

    assert_enqueued_with(job: FetchModeratorAvatarJob, args: [ @moderator ]) { @moderator.refresh_avatar_later }
  end

  test "an unchanged one is not fetched again" do
    @moderator.update!(avatar_url: "https://files.example/a.png")
    @moderator.create_avatar!(image: PNG, content_type: "image/png", source_url: "https://files.example/a.png")

    assert_no_enqueued_jobs(only: FetchModeratorAvatarJob) { @moderator.refresh_avatar_later }
  end

  test "nothing is fetched before consent, and consenting fetches it" do
    @moderator.update!(avatar_url: "https://files.example/a.png", consented_at: nil)

    assert_no_enqueued_jobs(only: FetchModeratorAvatarJob) { @moderator.refresh_avatar_later }
    assert_enqueued_with(job: FetchModeratorAvatarJob) { @moderator.consent! }
  end

  test "forgetting a moderator forgets their avatar" do
    @moderator.create_avatar!(image: PNG, content_type: "image/png", source_url: "https://files.example/a.png")

    @moderator.forget!

    assert_not Moderator::Avatar.exists?(moderator_id: @moderator.id)
  end

  test "the version changes with the image" do
    assert_nil @moderator.avatar_version

    avatar = @moderator.create_avatar!(image: PNG, content_type: "image/png", source_url: "https://files.example/a.png")
    first = @moderator.avatar_version
    avatar.update!(image: PNG + "x".b)

    assert_not_equal first, @moderator.avatar_version
  end
end
