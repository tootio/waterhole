require "test_helper"

class MailInfrastructure::LookupTest < ActiveSupport::TestCase
  include LoopbackNameserver::Helpers

  Answer = Struct.new(:records, :names, :addresses, :resolved) do
    def mx_records(name)
      (self.names ||= []) << name
      records
    end

    def address_records(name)
      (self.resolved ||= []) << name
      addresses.to_a
    end
  end

  def lookup(records, domain = "example.org")
    MailInfrastructure::Lookup.stub_resolver(Answer.new(records)) { MailInfrastructure::Lookup.call(domain) }.fetch(:hosts)
  end

  def addresses_with(*addresses)
    answer = Answer.new([ [ 10, "mx.example.net" ] ], nil, addresses)
    MailInfrastructure::Lookup.stub_resolver(answer) { MailInfrastructure::Lookup.call("example.org") }.fetch(:addresses)
  end

  test "the addresses of the hosts come back in one spelling, each once" do
    assert_equal %w[2a01:4f8::1 8.8.8.8], addresses_with("8.8.8.8", "2A01:4F8:0:0:0:0:0:1", "8.8.8.8")
  end

  test "a private or reserved address is no evidence of anything" do
    assert_equal %w[8.8.8.8], addresses_with("127.0.0.1", "10.0.0.1", "192.0.2.1", "::1", "8.8.8.8")
  end

  test "an applicant's domain cannot have many hosts resolved, or many addresses stored" do
    many = (1..10).map { [ it, "mx#{it}.example.net" ] }
    answer = Answer.new(many, nil, (1..50).map { "8.8.8.#{it}" })

    found = MailInfrastructure::Lookup.stub_resolver(answer) { MailInfrastructure::Lookup.call("example.org") }

    assert_equal %w[mx1.example.net. mx2.example.net. mx3.example.net.], answer.resolved
    assert_equal MailInfrastructure::Lookup::MAX_ADDRESSES, found[:addresses].size
  end

  test "the best hosts' addresses are the ones kept when there are too many" do
    best = Class.new do
      def mx_records(_) = [ [ 10, "primary.example.net" ], [ 20, "backup.example.net" ] ]

      def address_records(name)
        name.start_with?("primary") ? %w[94.130.108.80] : (1..50).map { "8.8.8.#{it}" }
      end
    end.new

    found = MailInfrastructure::Lookup.stub_resolver(best) { MailInfrastructure::Lookup.call("example.org") }

    assert_includes found[:addresses], "94.130.108.80"
    assert_equal MailInfrastructure::Lookup::MAX_ADDRESSES, found[:addresses].size
  end

  test "one host failing to resolve costs only its own addresses" do
    lame_backup = Class.new do
      def mx_records(_) = [ [ 10, "mxslurp.click" ], [ 20, "stale-backup.example.net" ] ]

      def address_records(name)
        name.start_with?("stale") ? raise(Resolv::ResolvError, "down") : %w[8.8.8.8]
      end
    end.new

    found = MailInfrastructure::Lookup.stub_resolver(lame_backup) { MailInfrastructure::Lookup.call("example.org") }

    assert_equal %w[mxslurp.click stale-backup.example.net], found[:hosts]
    assert_equal %w[8.8.8.8], found[:addresses]
  end

  test "a resolver failure on the addresses of every host fails the whole lookup" do
    failing = Class.new do
      def mx_records(_) = [ [ 10, "mx.example.net" ] ]
      def address_records(_) = raise(Resolv::ResolvError, "down")
    end.new

    MailInfrastructure::Lookup.stub_resolver(failing) do
      assert_raises(Resolv::ResolvError) { MailInfrastructure::Lookup.call("example.org") }
    end
  end

  test "hosts come back normalised, best preference first" do
    assert_equal %w[a.example.net b.example.net c.example.net],
      lookup([ [ 20, "C.example.net" ], [ 10, "b.example.net" ], [ 5, "a.EXAMPLE.net" ] ])
  end

  test "equal preferences come back in a fixed order, because DNS rotates them" do
    assert_equal lookup([ [ 10, "a.example" ], [ 10, "b.example" ] ]), lookup([ [ 10, "b.example" ], [ 10, "a.example" ] ])
  end

  test "a null MX is no host" do
    assert_empty lookup([ [ 0, "" ] ])
  end

  test "an applicant's domain cannot store an arbitrary answer" do
    many = (1..50).map { [ it, "mx#{it}.example.net" ] }
    assert_equal MailInfrastructure::Lookup::MAX_HOSTS, lookup(many).size
    assert_equal %w[mx.example.net], lookup([ [ 1, "<script>.example.net" ], [ 2, "mx.example.net" ] ])
  end

  test "something that is not a hostname is never sent to DNS" do
    answer = Answer.new([ [ 10, "mx.example.net" ] ])

    MailInfrastructure::Lookup.stub_resolver(answer) do
      [ "", nil, "localhost", "bad domain.example", "#{"a" * 64}.example" ].each do
        assert_equal MailInfrastructure::Lookup::NOTHING, MailInfrastructure::Lookup.call(it)
      end
    end
    assert_nil answer.names
  end

  test "the query is for the absolute name, so no search domain gets appended" do
    answer = Answer.new([])
    MailInfrastructure::Lookup.stub_resolver(answer) { MailInfrastructure::Lookup.call("example.org") }

    assert_equal [ "example.org." ], answer.names
  end

  Failing = Class.new { def mx_records(_) = raise(Resolv::ResolvError, "down") }

  def with_cache
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = previous
  end

  test "answers are cached, a failure is not" do
    answer = Answer.new([ [ 10, "mx.example.net" ] ])

    with_cache do
      MailInfrastructure::Lookup.stub_resolver(Failing.new) do
        assert_raises(Resolv::ResolvError) { MailInfrastructure::Lookup.call("example.org") }
      end

      MailInfrastructure::Lookup.stub_resolver(answer) do
        2.times { assert_equal %w[mx.example.net], MailInfrastructure::Lookup.call("example.org")[:hosts] }
      end
    end

    assert_equal 1, answer.names.size
  end

  test "a failure is remembered for a while" do
    with_cache do
      assert_not MailInfrastructure::Lookup.recently_failed?("example.org")

      MailInfrastructure::Lookup.stub_resolver(Failing.new) do
        assert_raises(Resolv::ResolvError) { MailInfrastructure::Lookup.call("example.org") }
      end
      assert MailInfrastructure::Lookup.recently_failed?("example.org")

      travel MailInfrastructure::Lookup::FAILURE_BACKOFF + 1.minute
      assert_not MailInfrastructure::Lookup.recently_failed?("example.org")
    end
  end

  test "deleting a request takes its domain out of the cache" do
    request = registration_requests(:pending_alpha)
    request.update!(email: "someone@example.org")

    with_cache do
      lookup([ [ 10, "mx.example.net" ] ])
      MailInfrastructure::Lookup.stub_resolver(Failing.new) do
        assert_raises(Resolv::ResolvError) { MailInfrastructure::Lookup.call("failing.example") }
      end
      assert Rails.cache.exist?("mail_infrastructure/mx/example.org")

      request.purge!
      assert_not Rails.cache.exist?("mail_infrastructure/mx/example.org")

      MailInfrastructure::Lookup.forget("failing.example")
      assert_not MailInfrastructure::Lookup.recently_failed?("failing.example")
    end
  end

  test "a changed address takes the old domain out of the cache, leaving the new one" do
    request = registration_requests(:pending_alpha)
    request.update!(email: "someone@example.org")

    with_cache do
      lookup([ [ 10, "mx.example.net" ] ])
      lookup([ [ 10, "mx.example.net" ] ], "example.net")

      request.update!(email: "someone@example.net")

      assert_not Rails.cache.exist?("mail_infrastructure/mx/example.org")
      assert Rails.cache.exist?("mail_infrastructure/mx/example.net")
    end
  end

  test "the real resolver returns what a nameserver answered" do
    answering(Resolv::DNS::RCode::NoError, [ Resolv::DNS::Resource::IN::MX.new(10, Resolv::DNS::Name.create("mx.example.net.")) ]) do |resolver|
      assert_equal [ [ 10, "mx.example.net" ] ], resolver.mx_records("example.org.")
    end
  end

  test "the real resolver returns both kinds of address, and none for a host without any" do
    records = [ Resolv::DNS::Resource::IN::A.new("8.8.8.8"), Resolv::DNS::Resource::IN::AAAA.new("2a01:4f8::1") ]

    answering(Resolv::DNS::RCode::NoError, records) do |resolver|
      assert_equal %w[8.8.8.8 2a01:4f8::1], resolver.address_records("mx.example.net.")
    end
    answering(Resolv::DNS::RCode::NXDomain) { |resolver| assert_empty resolver.address_records("mx.example.net.") }
    answering(Resolv::DNS::RCode::ServFail) do |resolver|
      assert_raises(Resolv::ResolvError) { resolver.address_records("mx.example.net.") }
    end
  end

  test "the real resolver keeps one kind of address when the other kind fails" do
    a = Resolv::DNS::Resource::IN::A
    aaaa = Resolv::DNS::Resource::IN::AAAA

    answering({ aaaa => Resolv::DNS::RCode::ServFail }, [ a.new("8.8.8.8") ]) do |resolver|
      assert_equal %w[8.8.8.8], resolver.address_records("mx.example.net.")
    end
    answering({ a => Resolv::DNS::RCode::ServFail, aaaa => Resolv::DNS::RCode::Refused }) do |resolver|
      assert_raises(Resolv::ResolvError) { resolver.address_records("mx.example.net.") }
    end
  end

  test "the real resolver takes no records and no such domain for answers" do
    [ Resolv::DNS::RCode::NoError, Resolv::DNS::RCode::NXDomain ].each do |rcode|
      answering(rcode) { |resolver| assert_empty resolver.mx_records("example.org.") }
    end
  end

  test "the real resolver raises when the nameserver failed, rather than reading as no records" do
    [ Resolv::DNS::RCode::ServFail, Resolv::DNS::RCode::Refused ].each do |rcode|
      answering(rcode) do |resolver|
        assert_raises(Resolv::ResolvError) { resolver.mx_records("example.org.") }
      end
    end
  end
end
