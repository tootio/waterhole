require "test_helper"

# One record per deployment, as SPF, DMARC and MTA-STS allow one per name: DNS
# returns record sets in no fixed order, so choosing among several would make
# the outcome depend on the order of the answer.
class DnsAmbiguityTest < ActiveSupport::TestCase
  HOST = Waterhole::Deployment.host

  setup { @instance = instances(:alpha) }

  def check(*records) = DnsAllowlist.call("alpha.example", resolver: dns_records(records))

  def verify_with(*records) = verify_against(@instance, dns_records(records))

  test "two different records for this deployment are ambiguous, in either order" do
    a = txt_record(signals: true)
    b = txt_record

    assert check(a, b).ambiguous?
    assert check(b, a).ambiguous?
  end

  test "records that differ only in spacing, case or key order are one record" do
    result = check(txt_record(signals: true), "HOST=#{HOST.upcase};v=WATERHOLE1;  SIGNALS=ON")

    assert result.verified?
    assert result.signals
  end

  test "records for other deployments do not count" do
    assert check(txt_record, "v=waterhole1; host=other.example; signals=on").verified?
  end

  test "sign-in is refused with an explanation" do
    result = DnsAllowlist.stub_resolver(dns_records([ txt_record(signals: true), txt_record ])) do
      Admission.call("alpha.example")
    end

    refute result.admitted?
    assert_equal :dns_ambiguous, result.outcome
    assert result.fixable_by_admin?
    assert_match(/Keep exactly one/, result.message)
  end

  test "an existing instance keeps access and its signals for a while, then loses access" do
    conflicting = [ txt_record(signals: true), txt_record ]

    2.times { verify_with(*conflicting) }
    assert @instance.verified?, "a republish can have old and new records up side by side"
    assert @instance.signals_opted_in?, "participation must not follow whichever record came first"

    verify_with(*conflicting)
    assert @instance.revoked?
    assert_match(/more than one different record/, @instance.verification_detail)
  end
end
