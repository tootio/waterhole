require "test_helper"

class ClaimsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @moderator = moderators(:avery)
    @pending = registration_requests(:pending_alpha)
    sign_in_as @moderator
  end

  test "claiming an unclaimed request succeeds" do
    instance_stream = Turbo::StreamsChannel.send(:stream_name_from, [ @pending.instance, :registration_requests ])
    request_stream = Turbo::StreamsChannel.send(:stream_name_from, @pending)

    perform_enqueued_jobs do
      post registration_request_claim_path(@pending)
    end

    assert_equal @moderator, @pending.reload.claimed_by
    assert @pending.claimed_at.present?
    assert broadcasts(instance_stream).any?, "expected a refresh broadcast on the instance stream"
    assert broadcasts(request_stream).any?, "expected a refresh broadcast on the request stream"
  end

  test "claiming something someone else already holds does not steal it" do
    claimed = registration_requests(:claimed_alpha)

    post registration_request_claim_path(claimed)

    assert_equal moderators(:blake), claimed.reload.claimed_by,
      "a second claim must not silently take the request"
    assert_match(/claimed this first/, flash[:alert])
  end

  test "a fresh claim cannot be forced" do
    claimed = registration_requests(:claimed_alpha)

    post registration_request_claim_path(claimed, force: 1)

    assert_equal moderators(:blake), claimed.reload.claimed_by,
      "taking over should only be possible once a claim has gone stale"
  end

  test "a stale claim can be taken over deliberately" do
    claimed = registration_requests(:claimed_alpha)
    claimed.update!(claimed_at: 5.hours.ago)

    post registration_request_claim_path(claimed, force: 1)

    assert_equal @moderator, claimed.reload.claimed_by
  end

  test "releasing frees the request" do
    @pending.update!(claimed_by: @moderator, claimed_at: Time.current)

    delete registration_request_claim_path(@pending)

    assert_nil @pending.reload.claimed_by
  end

  test "claiming via turbo stream responds with turbo stream replacing the request" do
    post registration_request_claim_path(@pending), as: :turbo_stream

    assert_response :success
    assert_equal @moderator, @pending.reload.claimed_by
    assert_match(/<turbo-stream action="replace" target="registration_request_#{@pending.id}">/, response.body)
    assert_match(/Yours/, response.body)
  end

  test "releasing via turbo stream responds with turbo stream replacing the request" do
    @pending.update!(claimed_by: @moderator, claimed_at: Time.current)

    delete registration_request_claim_path(@pending), as: :turbo_stream

    assert_response :success
    assert_nil @pending.reload.claimed_by
    assert_match(/<turbo-stream action="replace" target="registration_request_#{@pending.id}">/, response.body)
    refute_match(/Yours/, response.body)
  end

  # The conditional UPDATE is what makes this safe; a read-then-write would let
  # both moderators believe they won.
  test "only one of two simultaneous claims wins" do
    won = [ moderators(:avery), moderators(:blake) ].count do |moderator|
      RegistrationRequest.where(id: @pending.id, claimed_by_id: nil)
        .update_all(claimed_by_id: moderator.id, claimed_at: Time.current) == 1
    end

    assert_equal 1, won
  end
end
