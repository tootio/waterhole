require "test_helper"

class Flags::MailProviderRuleTest < ActiveSupport::TestCase
  setup { @request = registration_requests(:pending_alpha) }

  def observe(hosts, email: nil)
    @request.update!(email:) if email
    @request.update!(email_mx_hosts: hosts, email_mx_checked_at: Time.current)
    @request.recompute_flags!
    @request.reload
  end

  def mail_flags = @request.flags.where(rule: Flags::MailProviderRule.rule_names)

  test "every provider is a registered rule named after its key" do
    assert_equal MailInfrastructure::PROVIDERS.map(&:key), Flags::MailProviderRule.rule_names
    assert_empty Flags::MailProviderRule.rule_names - Flags.rule_names
  end

  test "every provider has a help text" do
    Flags::MailProviderRule.rule_names.each do |rule|
      assert I18n.exists?("flags.#{rule}.help", :en), "missing flags.#{rule}.help in config/locales/en.yml"
    end
    assert_equal "Amazon SES inbound", Flag.label_for("amazon_ses_inbound")
  end

  test "the flag carries the provider's severity and its evidence" do
    observe(%w[inbound-smtp.us-east-1.amazonaws.com], email: "someone@example.org")

    flag = mail_flags.sole
    assert_equal "amazon_ses_inbound", flag.rule
    assert_equal "warning", flag.severity
    assert_equal({ "domain" => "example.org", "matched" => "inbound-smtp.us-east-1.amazonaws.com", "via" => "mx" }, flag.details)
  end

  test "information about a mainstream provider is only info" do
    observe(%w[gmail-smtp-in.l.google.com], email: "someone@gmail.com")

    assert_equal [ %w[gmail info] ], mail_flags.pluck(:rule, :severity)
  end

  test "a listed domain is flagged before any lookup has happened" do
    @request.update!(email: "bot@agentmail.to")
    @request.recompute_flags!

    flag = @request.reload.flags.find_by!(rule: "ai_bot")
    assert_equal "critical", flag.severity
    assert_equal "domain", flag.details["via"]
  end

  test "flags follow the stored hosts, so a catalogue change needs no new lookup" do
    observe(%w[mail.example.org], email: "someone@example.org")
    assert_empty mail_flags

    @request.update_columns(email_mx_hosts: %w[mxslurp.click])
    @request.recompute_flags!
    assert_equal %w[test_mail], mail_flags.pluck(:rule)
  end

  test "a decided request keeps the flags it was decided on" do
    observe(%w[gmail-smtp-in.l.google.com], email: "someone@gmail.com")
    @request.update!(status: "rejected", resolved_at: Time.current)

    @request.update_columns(email_mx_hosts: %w[mxslurp.click])
    @request.recompute_flags!

    assert_equal %w[gmail], mail_flags.pluck(:rule)
  end

  test "a decided request keeps its hosts when its address changes, it will not be looked up again" do
    observe(%w[gmail-smtp-in.l.google.com], email: "someone@gmail.com")
    @request.update!(status: "rejected", resolved_at: Time.current)

    @request.update!(email: "someone@example.org")

    assert_equal %w[gmail-smtp-in.l.google.com], @request.reload.email_mx_hosts
  end

  test "a copy that predates the lookup does not take its flag away" do
    stale = RegistrationRequest.find(@request.id)
    observe(%w[mxslurp.click], email: "someone@example.org")

    stale.recompute_flags!

    assert_equal %w[test_mail], mail_flags.pluck(:rule)
    assert_equal @request.flags.count, @request.reload.flags_count
  end

  test "disposable mail is flagged when the blocklist doesn't know the domain" do
    observe(%w[tinyhost.shop], email: "someone@example.org")

    assert_equal [ %w[disposable_mail warning] ], mail_flags.pluck(:rule, :severity)
  end

  test "flags follow the stored addresses too, so a catalogue change needs no new lookup" do
    observe(%w[mx.new-throwaway.example], email: "someone@example.org")
    assert_empty mail_flags

    @request.update_columns(email_mx_addresses: %w[78.47.124.133])
    @request.recompute_flags!

    assert_equal [ %w[disposable_mail warning] ], mail_flags.pluck(:rule, :severity)
  end

  test "an address match gives no second flag when the blocklist already said so" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        DomainLists::DisposableEmailDomains.path.write("example.org\n")
        @request.update!(email: "someone@example.org", email_mx_addresses: %w[78.47.124.133], email_mx_checked_at: Time.current)
        @request.recompute_flags!
      end
    end

    assert_empty mail_flags
  end

  test "disposable mail gives no second flag when the blocklist already said so" do
    Dir.mktmpdir do |dir|
      DomainLists::DisposableEmailDomains.stub_directory(dir) do
        File.write(DomainLists::DisposableEmailDomains.path, "example.org\n")

        observe(%w[tinyhost.shop], email: "someone@example.org")
      end
    end

    assert_empty mail_flags
    assert @request.flags.exists?(rule: "disposable_email")
  end

  test "a request purged since the caller loaded it is no error, so a sweep carries on" do
    stale = RegistrationRequest.find(@request.id)
    @request.purge!

    assert_nothing_raised { stale.recompute_flags! }
  end

  test "a sweep's preloaded instance is what the rules read" do
    loaded = RegistrationRequest.includes(:instance).find(@request.id)

    assert_queries_match(/FROM "instances"/, count: 0) { loaded.recompute_flags! }
  end

  test "a subsumed provider gets no flag, though it matches on its own" do
    observe(%w[mxa.mailgun.org], email: "bot@agentmail.to")

    assert_equal %w[ai_bot], mail_flags.pluck(:rule)
  end

  test "a flag of a rule that no longer exists leaves the pending queue" do
    observe(%w[mail.example.org], email: "someone@example.org")
    @request.flags.create!(rule: "retired_provider", severity: "critical", details: {})

    @request.recompute_flags!

    assert_not @request.flags.exists?(rule: "retired_provider")
    assert_equal @request.flags.count, @request.reload.flags_count
  end

  test "a decided request keeps a flag of a rule that no longer exists" do
    @request.flags.create!(rule: "retired_provider", severity: "critical", details: {})
    @request.update!(status: "rejected", resolved_at: Time.current)

    @request.recompute_flags!

    assert @request.flags.exists?(rule: "retired_provider")
  end

  test "a new email domain forgets what was seen for the old one" do
    observe(%w[gmail-smtp-in.l.google.com], email: "someone@gmail.com")

    @request.update!(email: "someone@example.org")

    assert_nil @request.email_mx_hosts
    assert_nil @request.email_mx_checked_at
    assert_predicate @request, :needs_mail_infrastructure_lookup?
  end

  test "a new email domain forgets what the lookup stored since this copy was loaded" do
    @request.update!(email: "someone@example.org")
    stale = RegistrationRequest.find(@request.id)
    observe(%w[gmail-smtp-in.l.google.com])

    @request.update_columns(email_mx_addresses: %w[8.8.8.8])

    stale.update!(email: "someone@example.net")

    assert_nil @request.reload.email_mx_hosts
    assert_nil @request.email_mx_addresses
    assert_nil @request.email_mx_checked_at
  end

  test "a domain changed without the address changing forgets too, as the rehash task does" do
    observe(%w[gmail-smtp-in.l.google.com], email: "someone@gmail.com")

    @request.email_domain = "googlemail.com"
    @request.save!

    assert_nil @request.reload.email_mx_hosts
  end

  test "a new address on the same domain keeps it" do
    observe(%w[gmail-smtp-in.l.google.com], email: "someone@gmail.com")

    @request.update!(email: "someone.else@gmail.com")

    assert_equal %w[gmail-smtp-in.l.google.com], @request.email_mx_hosts
  end
end
