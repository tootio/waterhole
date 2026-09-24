require "test_helper"

class VotesTest < ActionDispatch::IntegrationTest
  setup do
    @moderator = moderators(:avery)
    @subject = registration_requests(:claimed_alpha)
    sign_in_as @moderator
  end

  test "casting a vote records it against the moderator" do
    assert_difference -> { @subject.votes.count }, 1 do
      patch registration_request_vote_path(@subject), params: { vote: "reject" }
    end

    assert_redirected_to registration_request_path(@subject)
    assert @subject.votes.find_by!(moderator: @moderator).vote_reject?
  end

  test "voting again changes the vote rather than adding one" do
    patch registration_request_vote_path(@subject), params: { vote: "approve" }

    assert_no_difference -> { @subject.votes.count } do
      patch registration_request_vote_path(@subject), params: { vote: "reject" }
      patch registration_request_vote_path(@subject), params: { vote: "reject" }
    end
    assert @subject.votes.find_by!(moderator: @moderator).vote_reject?
  end

  test "a moderator withdraws only their own vote" do
    patch registration_request_vote_path(@subject), params: { vote: "approve" }

    assert_difference -> { @subject.votes.count }, -1 do
      delete registration_request_vote_path(@subject)
    end
    refute @subject.votes.exists?(moderator: @moderator)
    assert @subject.votes.exists?(moderator: moderators(:blake))
  end

  test "an unknown vote is refused" do
    assert_no_difference -> { Vote.count } do
      patch registration_request_vote_path(@subject), params: { vote: "maybe" }
    end
  end

  test "voting on another instance's request is not found" do
    patch registration_request_vote_path(registration_requests(:other_instance)), params: { vote: "approve" }

    assert_response :not_found
  end

  test "voting is closed once a request is decided" do
    decided = registration_requests(:rejected_alpha)

    assert_no_difference -> { Vote.count } do
      patch registration_request_vote_path(decided), params: { vote: "approve" }
    end
    assert_equal "Voting is closed once a request is decided.", flash[:alert]
  end

  test "the request page shows the tally and the moderator's own vote" do
    patch registration_request_vote_path(@subject), params: { vote: "reject" }
    get registration_request_path(@subject)

    assert_select "h2", /Moderator notes and votes/
    assert_select "#votes dt", text: "1 approve"
    assert_select "#votes dt", text: "1 reject"
    assert_select "#votes button[aria-pressed=true]", text: /Reject/
  end

  test "a decided request shows the tally without vote buttons" do
    registration_requests(:rejected_alpha).votes.create!(moderator: @moderator, vote: "reject")
    get registration_request_path(registration_requests(:rejected_alpha))

    assert_select "#votes dt", text: "1 reject"
    assert_select "#votes button", count: 0
  end

  test "the database holds one vote per moderator and request" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Vote.insert!({ registration_request_id: @subject.id, moderator_id: moderators(:blake).id, vote: "reject" })
    end
  end
end
