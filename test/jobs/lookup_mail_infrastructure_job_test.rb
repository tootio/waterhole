require "test_helper"

class LookupMailInfrastructureJobTest < ActiveJob::TestCase
  Answer = Struct.new(:hosts, :during, :addresses) do
    def mx_records(_name)
      during&.call
      hosts.each_with_index.map { |host, index| [ index, host ] }
    end

    def address_records(_name) = addresses.to_a
  end

  Failing = Class.new { def mx_records(_name) = raise(Resolv::ResolvTimeout, "no answer") }

  setup do
    @request = registration_requests(:pending_alpha)
    @request.update!(email: "someone@example.org")
  end

  def run_with(resolver)
    MailInfrastructure::Lookup.stub_resolver(resolver) { LookupMailInfrastructureJob.perform_now(@request) }
    @request.reload
  end

  test "stores what was seen and flags the request" do
    freeze_time do
      run_with(Answer.new(%w[inbound-smtp.us-east-1.amazonaws.com]))

      assert_equal %w[inbound-smtp.us-east-1.amazonaws.com], @request.email_mx_hosts
      assert_equal Time.current, @request.email_mx_checked_at
      assert @request.flags.exists?(rule: "amazon_ses_inbound", severity: "warning")
      assert_equal @request.flags.count, @request.flags_count
    end
  end

  test "a new domain on a known service's server is flagged by the address" do
    run_with(Answer.new(%w[mx.new-throwaway.example], nil, %w[78.47.124.133]))

    assert_equal %w[78.47.124.133], @request.email_mx_addresses
    flag = @request.flags.find_by!(rule: "disposable_mail")
    assert_equal "ip", flag.details["via"]
    assert_equal "78.47.124.133", flag.details["matched"]
  end

  test "a resolver failure on the addresses stores nothing either" do
    failing = Class.new do
      def mx_records(_name) = [ [ 10, "mx.example.org" ] ]
      def address_records(_name) = raise(Resolv::ResolvTimeout, "no answer")
    end.new

    run_with(failing)

    assert_nil @request.email_mx_hosts
    assert_nil @request.email_mx_addresses
    assert_predicate @request, :needs_mail_infrastructure_lookup?
  end

  test "no records is an answer, and stops the asking" do
    run_with(Answer.new([]))

    assert_equal [], @request.email_mx_hosts
    assert_predicate @request.email_mx_checked_at, :present?
    assert_not_predicate @request, :needs_mail_infrastructure_lookup?
  end

  test "a resolver failure stores nothing, so the next sync asks again" do
    run_with(Failing.new)

    assert_nil @request.email_mx_hosts
    assert_nil @request.email_mx_checked_at
    assert_predicate @request, :needs_mail_infrastructure_lookup?
  end

  test "a failing recompute takes the stamp with it, so the next sync asks again" do
    failing = Class.new(ActiveRecord::Deadlocked).new("deadlock")
    Flags::Recompute.singleton_class.alias_method :real_call, :call
    Flags::Recompute.define_singleton_method(:call) { |_request| raise failing }

    assert_raises(ActiveRecord::Deadlocked) { run_with(Answer.new(%w[mxslurp.click])) }

    @request.reload
    assert_nil @request.email_mx_hosts
    assert_predicate @request, :needs_mail_infrastructure_lookup?
  ensure
    Flags::Recompute.singleton_class.alias_method :call, :real_call
    Flags::Recompute.singleton_class.remove_method :real_call
  end

  test "a domain that just failed is not asked again by jobs already queued" do
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    MailInfrastructure::Lookup.stub_resolver(Failing.new) do
      assert_raises(Resolv::ResolvTimeout) { MailInfrastructure::Lookup.call("example.org") }
    end

    run_with(Answer.new(%w[mxslurp.click], -> { flunk "asked DNS again during the backoff" }))

    assert_nil @request.email_mx_checked_at
  ensure
    Rails.cache = previous
  end

  test "the failure log does not name the applicant's domain" do
    # What Resolv itself raises: its message names what was asked for.
    naming_it = Class.new { def mx_records(name) = raise(Resolv::ResolvError, "DNS resolv timeout: #{name}") }
    logged = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)

    run_with(naming_it.new)

    assert_match(/MX lookup failed for request #{@request.id}: Resolv::ResolvError/, logged.string)
    assert_no_match(/example\.org/, logged.string)
  ensure
    Rails.logger = previous
  end

  test "an answer arriving after the request was purged leaves nothing in the cache" do
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    id = @request.id
    purge = -> { RegistrationRequest.find(id).purge! }

    MailInfrastructure::Lookup.stub_resolver(Answer.new(%w[mx.example.net], purge)) do
      LookupMailInfrastructureJob.perform_now(@request)
    end

    assert_not Rails.cache.exist?("mail_infrastructure/mx/example.org")
  ensure
    Rails.cache = previous
  end

  test "an answer arriving after the address changed leaves nothing about the old domain in the cache" do
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    id = @request.id
    change = -> { RegistrationRequest.find(id).update!(email: "someone@example.net") }

    run_with(Answer.new(%w[mx.example.net], change))

    assert_not Rails.cache.exist?("mail_infrastructure/mx/example.org")
  ensure
    Rails.cache = previous
  end

  test "a decided request is not looked up" do
    @request.update!(status: "approved", resolved_at: Time.current)
    answer = Answer.new(%w[mxslurp.click], -> { flunk "asked DNS about a decided request" })

    run_with(answer)

    assert_nil @request.email_mx_checked_at
  end

  test "one already looked up is not looked up again" do
    @request.update!(email_mx_hosts: %w[mail.example.org], email_mx_checked_at: 1.hour.ago)

    run_with(Answer.new(%w[mxslurp.click]))

    assert_equal %w[mail.example.org], @request.email_mx_hosts
  end

  test "an answer for the old domain is dropped when the address changed meanwhile" do
    id = @request.id
    change = -> { RegistrationRequest.find(id).update!(email: "someone@example.net") }

    run_with(Answer.new(%w[mxslurp.click], change))

    assert_equal "example.net", @request.email_domain
    assert_nil @request.email_mx_hosts
    assert_not @request.flags.exists?(rule: "test_mail")
  end

  test "a request purged before the job ran is discarded" do
    MailInfrastructure::Lookup.stub_resolver(Answer.new(%w[mxslurp.click])) do
      LookupMailInfrastructureJob.perform_later(@request)
      @request.purge!

      assert_nothing_raised { perform_enqueued_jobs(only: LookupMailInfrastructureJob) }
    end
  end
end
