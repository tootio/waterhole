require "test_helper"

class VerificationTest < ActionDispatch::IntegrationTest
  test "the verification page is public" do
    get verification_path
    assert_response :success
  end

  # Turbo rejects a 200 HTML body for a form submission with
  # "Form responses must redirect to another location", so this action must
  # redirect rather than render.
  test "checking a domain redirects instead of rendering" do
    DnsAllowlist.stub_resolver(dns_records([])) do
      post verification_path, params: { instance_domain: "example.social" }
    end

    assert_response :redirect
    assert_redirected_to verification_path(instance_domain: "example.social")
  end

  # :domain is a reserved url_for option -- it sets the URL's own domain -- so
  # verification_path(domain: x) silently yields "/verification" and the admin
  # lands on an empty form having lost what they typed.
  test "the domain survives the redirect" do
    assert_includes verification_path(instance_domain: "example.social"),
      "instance_domain=example.social"
    assert_not_includes verification_path(instance_domain: "example.social"), "?domain="
  end

  test "the page shows the record to publish, including the terms digest" do
    with_legal_documents do
      DnsAllowlist.stub_resolver(dns_records([])) do
        get verification_path, params: { instance_domain: "example.social" }
      end

      assert_response :success
      assert_select "body", /_waterhole\.example\.social/
      assert_match(/accepted=#{LegalDocuments.digest}/, response.body)
    end
  end

  # sessions/blocked renders the same partial, so the frame the "Check again"
  # button targets has to exist there too.
  test "the result frame is present wherever the instructions render" do
    DnsAllowlist.stub_resolver(dns_records([])) do
      get verification_path, params: { instance_domain: "example.social" }
      assert_select "turbo-frame#verification_result"

      post session_path, params: { domain: "newcomer.example" }
      assert_response :forbidden
      assert_select "turbo-frame#verification_result"
    end
  end

  test "a verified domain reports success" do
    with_legal_documents do
      instances(:alpha).update!(accepted_terms_digest: LegalDocuments.digest)

      DnsAllowlist.stub_resolver(dns_record(accepted: LegalDocuments.digest)) do
        get verification_path, params: { instance_domain: "alpha.example" }
      end

      assert_select "body", /authorised/i
    end
  end

  test "the first step links all three documents" do
    with_legal_documents do
      DnsAllowlist.stub_resolver(dns_records([])) { get verification_path(instance_domain: "newcomer.example") }
    end

    assert_select "h2", "1. Read the terms, and decide"
    assert_select "a[href=?]", terms_path
    assert_select "a[href=?]", privacy_path
    assert_select "a[href=?]", imprint_path
    assert_select "span", { count: 0, text: "changed" }
  end

  test "a record accepting older documents is told which ones changed" do
    accepted = nil
    with_legal_documents { accepted = LegalDocuments.digest }

    with_legal_documents(imprint: "# Imprint\n\nOperated by Someone Else.\n") do
      DnsAllowlist.stub_resolver(dns_record(accepted: accepted)) do
        get verification_path(instance_domain: "newcomer.example")
      end
    end

    assert_select "li", /Imprint.*changed/m
    assert_select "li", { count: 0, text: /Terms of Service.*changed/m }
    assert_select "p", /earlier version of the\s+imprint/
  end

  # Regression: the record shown for republishing dropped signals=on, so an
  # admin accepting new terms silently opted out of cross-instance signals.
  test "the record to republish keeps an existing signals opt-in" do
    with_legal_documents do
      DnsAllowlist.stub_resolver(dns_records([ txt_record(accepted: "old", signals: true) ])) do
        get verification_path(instance_domain: "newcomer.example")
      end
    end

    assert_signals_choice "on"
  end

  test "the value can be copied on its own, for DNS provider forms" do
    with_legal_documents do
      DnsAllowlist.stub_resolver(dns_records([])) { get verification_path(instance_domain: "newcomer.example") }

      value = DnsAllowlist.expected_value
      assert_select "button[data-clipboard-value=?]", value, text: /value only/
      assert_select "button[data-clipboard-value=?]", DnsAllowlist.expected_record("newcomer.example"), text: /whole record/
      refute_includes value, '"'
    end
  end

  test "a record without accepted is told it accepts nothing yet, not an earlier version" do
    with_legal_documents do
      DnsAllowlist.stub_resolver(dns_record) { get verification_path(instance_domain: "newcomer.example") }
    end

    assert_select "p", /does not accept these documents yet/
    assert_select "p", { count: 0, text: /earlier version/ }
    assert_select "span", { count: 0, text: "changed" }
  end

  # With conflicting records the DNS answer says nothing about consent; the
  # opt-in last recorded for the instance decides what we suggest.
  test "with conflicting records the suggestion keeps the recorded opt-in" do
    instances(:alpha).update!(signals_opted_in: true)
    conflicting = dns_records([ txt_record(signals: true),
                                txt_record ])

    DnsAllowlist.stub_resolver(conflicting) { get verification_path(instance_domain: "alpha.example") }
    assert_signals_choice "on"

    instances(:alpha).update!(signals_opted_in: false)
    DnsAllowlist.stub_resolver(conflicting) { get verification_path(instance_domain: "alpha.example") }
    assert_signals_choice "off"
  end

  # Step 2 offers both records; the page starts on the one the admin chose.
  test "a new instance starts without signals, and both records are offered" do
    DnsAllowlist.stub_resolver(dns_records([])) { get verification_path(instance_domain: "newcomer.example") }

    assert_signals_choice "off"
    assert_select "[data-signals-choice-target=variant][data-signals=on] button[data-clipboard-value=?]",
      DnsAllowlist.expected_value(signals: true), text: /value only/
    assert_select "[data-signals-choice-target=variant][data-signals=off] button[data-clipboard-value=?]",
      DnsAllowlist.expected_value, text: /value only/
  end

  # The chosen option is checked, and only its record is shown.
  def assert_signals_choice(chosen)
    other = chosen == "on" ? "off" : "on"
    assert_select "input[type=radio][name=signals][value=#{chosen}][checked]"
    assert_select "input[type=radio][name=signals][value=#{other}][checked]", count: 0
    assert_select "[data-signals-choice-target=variant][data-signals=#{chosen}]:not([hidden])"
    assert_select "[data-signals-choice-target=variant][data-signals=#{other}][hidden]"
  end

  # Regression: the legal links sit inside the "Check again" frame, and Turbo
  # loaded them into it -- "Content missing" -- instead of opening the page.
  test "links inside the result frame open whole pages; only Check again stays in it" do
    DnsAllowlist.stub_resolver(dns_records([])) { get verification_path(instance_domain: "newcomer.example") }

    assert_select "turbo-frame#verification_result[target=_top]"
    assert_select "turbo-frame#verification_result form[data-turbo-frame=verification_result]"
  end

  # Applicants never see this Waterhole; the instance has to tell them.
  test "the admin is told to inform applicants, with a notice that follows the signals choice" do
    DnsAllowlist.stub_resolver(dns_records([])) { get verification_path(instance_domain: "newcomer.example") }

    assert_select "h2", "4. Tell your applicants"
    assert_select "strong", "Informing your applicants is your responsibility."
    assert_select "a[href=?]", "https://newcomer.example/admin/settings/about"
    assert_select "p", /Do we\s+disclose any information to outside parties\?.*your decision/m

    plain = "[data-signals-choice-target=variant][data-signals=off] button[data-clipboard-value]"
    shared = "[data-signals-choice-target=variant][data-signals=on] button[data-clipboard-value]"
    assert_select plain, text: /Copy text/ do |buttons|
      notice = buttons.first["data-clipboard-value"]
      assert_includes notice, Waterhole::Deployment.host
      assert_includes notice, "#{Waterhole::Deployment.base_url}/privacy"
      assert_no_match(/^#/, notice, "no heading of its own: it goes into an existing section")
      assert_includes notice, "#{Waterhole::Deployment.retention.in_days.to_i} days"
      refute_includes notice, "other servers that use it"
    end
    assert_select shared, text: /Copy text/ do |buttons|
      assert_includes buttons.first["data-clipboard-value"], "other servers that use it"
    end
  end
end
