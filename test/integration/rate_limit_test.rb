require "test_helper"

class RateLimitTest < ActionDispatch::IntegrationTest
  test "sign-in attempts are throttled per address" do
    DnsAllowlist.stub_resolver(dns_records([])) do
      10.times { post session_path, params: { domain: "newcomer.example" } }
      assert_response :forbidden, "the first ten reach the admission check"

      post session_path, params: { domain: "newcomer.example" }
    end

    assert_response :too_many_requests
    assert_equal "180", response.headers["Retry-After"]
    assert_select "h1", "Too many attempts"
  end

  test "the counter is per address" do
    DnsAllowlist.stub_resolver(dns_records([])) do
      10.times { post session_path, params: { domain: "newcomer.example" } }
      post session_path, params: { domain: "newcomer.example" }, env: { "REMOTE_ADDR" => "203.0.113.9" }
    end

    assert_response :forbidden
  end

  test "DNS checks from the public verification page are throttled" do
    DnsAllowlist.stub_resolver(dns_records([])) do
      10.times { post verification_path, params: { instance_domain: "newcomer.example" } }
      post verification_path, params: { instance_domain: "newcomer.example" }
    end

    assert_response :too_many_requests
  end

  test "manual syncs are throttled per instance, across its moderators" do
    sign_in_as moderators(:avery)
    5.times { post sync_path }
    assert_redirected_to root_path

    sign_in_as moderators(:blake)
    post sync_path

    assert_response :too_many_requests
  end
end
