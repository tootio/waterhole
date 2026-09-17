require "test_helper"

class RegistrationRequests::MapperTest < ActiveSupport::TestCase
  def ip_from(payload) = RegistrationRequests::Mapper.call(admin_account_payload(id: 1).merge(payload))[:ip]

  # Regression: the mapper once expected an object here, and the first real
  # pending account crashed every sync with TypeError.
  test "reads ip as the string Mastodon sends" do
    assert_equal "203.0.113.7", ip_from("ip" => "203.0.113.7")
  end

  test "falls back to the ips history when ip is null" do
    assert_equal "203.0.113.8",
      ip_from("ip" => nil, "ips" => [ { "ip" => "203.0.113.8", "used_at" => 1.hour.ago.iso8601 } ])
  end

  test "tolerates the object form" do
    assert_equal "203.0.113.9", ip_from("ip" => { "ip" => "203.0.113.9" })
  end

  test "no address at all is nil" do
    assert_nil ip_from("ip" => nil, "ips" => [])
  end

  test "keeps the app an account was created through, if any" do
    mapped = RegistrationRequests::Mapper.call(admin_account_payload(id: 1).merge("created_by_application_id" => "4711"))
    assert_equal "4711", mapped[:created_by_application_id]

    # Mastodon omits the key for sign-ups through the website's form.
    assert_nil RegistrationRequests::Mapper.call(admin_account_payload(id: 1))[:created_by_application_id]
  end
end
