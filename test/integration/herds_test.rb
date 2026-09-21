require "test_helper"

class HerdsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as moderators(:avery) }

  test "every herd at this waterhole is listed, not only your own" do
    get herds_path

    assert_response :success
    Instance.where.not(status: "blocked").each do |instance|
      assert_select "li", /#{Regexp.escape(instance.domain)}/,
        "expected #{instance.domain} in the list"
    end
  end

  test "each herd shows its status" do
    instances(:gamma).update!(status: "terms_outdated", terms_grace_until: 3.days.from_now)

    get herds_path

    assert_select "li", /Verified/
    assert_select "li", /Terms outdated/
    assert_select "li", /Unverified/
  end

  # The reciprocal fact: these are the herds yours is matched against.
  test "each herd shows whether it takes part in signals" do
    get herds_path

    assert_select "li", /Signals on/
    assert_select "li", /Signals off/
  end

  # Opting in is in the herd's own DNS record and is nobody's secret; the
  # operator's approval is a decision about that herd, and the two are shown
  # only as the one fact that concerns everyone else.
  test "a herd that opted in but was not approved reads as off, without saying why" do
    instances(:beta).update!(signals_opted_in: true, signals_approved: false)

    get herds_path

    assert_select "li", { text: /#{Regexp.escape(instances(:beta).domain)}.*Signals off/m },
      "an unapproved herd is not participating"
    assert_select "body", { text: /not approved/i, count: 0 },
      "why it is off is the operator's business, not the list's"
  end

  test "a blocked herd is not part of anything here" do
    instances(:beta).update!(status: "blocked")

    get herds_path

    assert_select "body", { text: /#{Regexp.escape(instances(:beta).domain)}/, count: 0 }
  end

  test "your own herd is marked, and every row leads to its own page" do
    get herds_path

    assert_select "li a[href=?]", herd_path(moderators(:avery).instance), { count: 1 }
    assert_select "li a[href=?]", herd_path(instances(:beta)), { count: 1 }
    assert_select "li", /Yours/
  end

  test "the domain blocklist is listed, with its source" do
    get herds_path

    assert_select "li", { text: /#{Regexp.escape(domain_policies(:blocked_spam).domain)}/ }
    assert_select "li", /Manual/
    assert_select "li", { text: /#{Regexp.escape(domain_policies(:blocked_synced).domain)}/ }
    assert_select "li", /IFTAS DNI/
  end
end
