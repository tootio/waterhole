require "test_helper"

class Flags::ReapplicationTest < ActiveSupport::TestCase
  setup do
    @rejected = registration_requests(:rejected_alpha)
    @request = registration_requests(:pending_alpha)
    @request.update!(email: @rejected.email)
  end

  def reject_another(confirmed:)
    @request.instance.registration_requests.create!(mastodon_account_id: SecureRandom.hex(8), username: "earlier",
      email: @rejected.email, signed_up_at: 1.day.ago, status: "rejected", resolved_at: Time.current, confirmed:)
  end

  def detail_text(flag)
    ApplicationController.render(partial: "registration_requests/flag_detail", locals: { flag: }).squish
  end

  test "an address confirmed on the rejected request is critical" do
    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "reapplication")
    assert_equal "critical", flag.severity
    assert_nil flag.details["address_verified"]
    assert_equal "matches 1 earlier rejected request by email", detail_text(flag)
  end

  test "an address never confirmed is a warning, and says why" do
    @rejected.update!(confirmed: false)
    @request.recompute_flags!

    flag = @request.reload.flags.find_by(rule: "reapplication")
    assert_equal "warning", flag.severity
    assert_equal "email", flag.details["matched_on"]
    assert_equal false, flag.details["address_verified"]
    assert_equal "matches 1 earlier rejected request by email (address never verified)", detail_text(flag)
  end

  test "several rejections, none confirmed, prove no more than one" do
    @rejected.update!(confirmed: false)
    reject_another(confirmed: false)

    detection = Flags::Reapplication.call(@request)

    assert_equal Flag.severities.fetch("warning"), detection.severity
    assert_equal 2, detection.details[:count]
  end

  test "one confirmed rejection among unconfirmed ones is enough" do
    @rejected.update!(confirmed: false)
    reject_another(confirmed: true)

    detection = Flags::Reapplication.call(@request)

    assert_equal Flag.severities.fetch("critical"), detection.severity
    assert_equal 2, detection.details[:count]
    assert_not detection.details.key?(:address_verified)
  end

  # The address someone else proved was theirs: this is them, or someone posing as them.
  test "an applicant's own unconfirmed address does not soften a confirmed rejection" do
    @request.update!(confirmed: false, disabled: true)

    assert_equal Flag.severities.fetch("critical"), Flags::Reapplication.call(@request).severity
  end

  test "rejected elsewhere counts the same way" do
    @rejected.update!(status: "rejected_elsewhere", confirmed: false)

    assert_equal Flag.severities.fetch("warning"), Flags::Reapplication.call(@request).severity
  end

  test "a network match does not claim an unverified address" do
    @rejected.update!(confirmed: false)
    @request.update!(email: "someone-new@example.org", ip: @rejected.ip)

    detection = Flags::Reapplication.call(@request)

    assert_equal "ip", detection.details[:matched_on]
    assert_not detection.details.key?(:address_verified)
  end
end
