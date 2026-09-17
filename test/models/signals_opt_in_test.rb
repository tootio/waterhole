require "test_helper"

# Cross-instance signals need two keys: `signals=on` in the instance admin's DNS
# record, and the operator's approval.
class SignalsOptInTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  HOST = Waterhole::Deployment.host

  setup { @instance = instances(:alpha) }

  def verify_with(*records)
    DnsAllowlist.stub_resolver(dns_records(records)) { VerifyInstanceJob.perform_now(@instance) }
    @instance.reload
  end

  test "the record's signals flag is read, and only `on` counts" do
    assert DnsAllowlist.call("alpha.example", resolver: dns_records([ "v=waterhole1; host=#{HOST}; signals=on" ])).signals
    assert DnsAllowlist.call("alpha.example", resolver: dns_records([ "v=waterhole1; host=#{HOST}; SIGNALS=ON" ])).signals
    refute DnsAllowlist.call("alpha.example", resolver: dns_records([ "v=waterhole1; host=#{HOST}" ])).signals
    refute DnsAllowlist.call("alpha.example", resolver: dns_records([ "v=waterhole1; host=#{HOST}; signals=yes" ])).signals
  end

  test "a record for another deployment cannot opt this one in" do
    result = DnsAllowlist.call("alpha.example",
      resolver: dns_records([ "v=waterhole1; host=#{HOST}", "v=waterhole1; host=other.example; signals=on" ]))

    assert result.verified?
    refute result.signals
  end

  test "with several records, the one accepting the current terms decides" do
    with_legal_documents do
      digest = LegalDocuments.digest
      result = DnsAllowlist.call("alpha.example", resolver: dns_records([
        "v=waterhole1; host=#{HOST}; accepted_tos=stale; signals=on",
        "v=waterhole1; host=#{HOST}; accepted_tos=#{digest}"
      ]))

      assert result.verified?
      refute result.signals, "the stale record's opt-in must not count"
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
    verify_with("v=waterhole1; host=#{HOST}; signals=on")
    assert @instance.signals_opted_in?
    assert @instance.participating?

    verify_with("v=waterhole1; host=#{HOST}")
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
