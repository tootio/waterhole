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
      assert_match(/accepted_tos=#{LegalDocuments.digest}/, response.body)
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

      DnsAllowlist.stub_resolver(dns_record(accepted_tos: LegalDocuments.digest)) do
        get verification_path, params: { instance_domain: "alpha.example" }
      end

      assert_select "body", /authorised/i
    end
  end
end
