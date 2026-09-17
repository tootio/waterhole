require "test_helper"

# Cross-instance signals need two keys: `signals=on` in the instance admin's DNS
# record, and the operator's approval.
class SignalsOptInTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  HOST = Waterhole::Deployment.host

  setup { @instance = instances(:alpha) }

  def verify_with(*records) = verify_against(@instance, dns_records(records))

  test "the record's signals flag is read, and only `on` counts" do
    assert DnsAllowlist.call("alpha.example", resolver: dns_records([ txt_record(signals: true) ])).signals
    assert DnsAllowlist.call("alpha.example", resolver: dns_records([ "v=waterhole1; host=#{HOST}; SIGNALS=ON" ])).signals
    refute DnsAllowlist.call("alpha.example", resolver: dns_records([ txt_record ])).signals
    refute DnsAllowlist.call("alpha.example", resolver: dns_records([ "v=waterhole1; host=#{HOST}; signals=yes" ])).signals
  end

  test "a record for another deployment cannot opt this one in" do
    result = DnsAllowlist.call("alpha.example",
      resolver: dns_records([ txt_record, "v=waterhole1; host=other.example; signals=on" ]))

    assert result.verified?
    refute result.signals
  end

  # Not a choice between them: which record DNS returns first is chance.
  test "an old and a new record side by side say nothing about consent" do
    with_legal_documents do
      digest = LegalDocuments.digest
      result = DnsAllowlist.call("alpha.example", resolver: dns_records([
        "v=waterhole1; host=#{HOST}; accepted=stale; signals=on",
        "v=waterhole1; host=#{HOST}; accepted=#{digest}"
      ]))

      assert result.ambiguous?
      assert_nil result.signals
    end
  end

  test "an unreachable resolver says nothing about consent" do
    assert_nil DnsAllowlist.call("alpha.example", resolver: dns_unreachable).signals
  end

  test "the expected record can include the opt-in" do
    assert_includes DnsAllowlist.expected_record("alpha.example", signals: true), "; signals=on\""
    refute_includes DnsAllowlist.expected_record("alpha.example"), "signals"
  end

  test "verification records the admin's consent, and its withdrawal" do
    verify_with(txt_record(signals: true))
    assert @instance.signals_opted_in?
    assert @instance.participating?

    verify_with(txt_record)
    refute @instance.signals_opted_in?
    refute @instance.participating?
    assert @instance.verified?, "dropping the flag leaves access alone"
  end

  test "a missing record withdraws consent at once, before access is revoked" do
    verify_with

    refute @instance.signals_opted_in?
    assert @instance.verified?, "access still waits for three strikes"
  end

  test "a DNS outage leaves consent as it was" do
    DnsAllowlist.stub_resolver(dns_unreachable) { VerifyInstanceJob.perform_now(@instance) }

    assert @instance.reload.signals_opted_in?
  end

  test "participating needs both keys" do
    @instance.update!(signals_opted_in: true, signals_approved: false)
    refute @instance.participating?
    refute_includes Instance.participating, @instance

    @instance.update!(signals_opted_in: false, signals_approved: true)
    refute @instance.participating?
    refute_includes Instance.participating, @instance

    @instance.update!(signals_opted_in: true, signals_approved: true)
    assert @instance.participating?
    assert_includes Instance.participating, @instance
  end

  test "a change of consent refreshes everyone's flags" do
    assert_enqueued_with(job: RefreshCrossInstanceFlagsJob) do
      @instance.update!(signals_opted_in: false)
    end
  end
end
