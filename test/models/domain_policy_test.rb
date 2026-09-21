require "test_helper"

class DomainPolicyTest < ActiveSupport::TestCase
  test "source defaults to manual" do
    policy = DomainPolicy.create!(domain: "fresh.example", kind: "blocked")
    assert policy.manual?
  end

  test "source accepts iftas_dni" do
    policy = DomainPolicy.create!(domain: "synced-fresh.example", kind: "blocked", source: "iftas_dni")
    assert policy.iftas_dni?
  end

  test "an unrecognised source is invalid" do
    policy = DomainPolicy.new(domain: "bad.example", kind: "blocked", source: "scraped")
    assert_not policy.valid?
    assert_includes policy.errors[:source], "is not included in the list"
  end
end
