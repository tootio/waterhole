require "test_helper"

class Flags::EmailActiveElsewhereTest < ActiveSupport::TestCase
  setup do
    @alpha = registration_requests(:jules_alpha)  # alpha.example, opted in
    @beta  = registration_requests(:jules_beta)   # beta.example,  opted in
    @gamma = registration_requests(:jules_gamma)  # gamma.example, opted OUT
  end

  test "the same person across two participating instances is flagged on both" do
    @alpha.recompute_flags!
    @beta.recompute_flags!

    assert @alpha.reload.flags.exists?(rule: "email_active_elsewhere")
    assert @beta.reload.flags.exists?(rule: "email_active_elsewhere")
  end

  test "plus extensions and dots do not hide a match" do
    assert_equal "Ju.les+alpha@gmail.com", @alpha.email
    assert_equal "jules@gmail.com", @beta.email
    assert_equal @alpha.canonical_email_hash, @beta.canonical_email_hash
  end

  test "an instance that has not opted in neither sees nor feeds the signal" do
    @gamma.recompute_flags!
    refute @gamma.reload.flags.exists?(rule: "email_active_elsewhere"),
      "gamma opted out, so it must not see other instances' applicants"

    @alpha.recompute_flags!
    named = @alpha.reload.flags.find_by(rule: "email_active_elsewhere").details["instances"]
    assert_equal [ "beta.example" ], named,
      "gamma opted out, so its applicants must not be disclosed to alpha"
  end

  test "only currently active requests count" do
    @beta.update!(status: "rejected", resolved_at: Time.current)
    @alpha.recompute_flags!

    refute @alpha.reload.flags.exists?(rule: "email_active_elsewhere"),
      "a rejected account is no longer in use, so it is not 'active elsewhere'"
  end

  test "a request with no email is not flagged" do
    @alpha.update!(email: nil)
    @alpha.recompute_flags!

    refute @alpha.reload.flags.exists?(rule: "email_active_elsewhere")
  end

  test "counterparts finds the other side, which is what drives the reverse recompute" do
    counterparts = Flags::EmailActiveElsewhere.counterparts(@alpha)

    assert_equal [ @beta.id ], counterparts.map(&:id),
      "without this the flag would only ever appear on the newest side and go stale"
  end
end
