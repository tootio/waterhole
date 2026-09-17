module IpStubs
  FIXTURE_DIR = Rails.root.join("test/fixtures/files/mmdb")

  # Points the lookup at the committed fixture databases. They are real MMDB
  # files, so the record schema we extract from is genuinely exercised.
  def with_ip_databases(&) = Ip::Databases.stub_directory(FIXTURE_DIR, &)

  # Addresses present in the fixtures (documentation ranges only).
  DATACENTER_V4  = "203.0.113.7"   # AS64500 Example Hosting LLC, US
  RESIDENTIAL_V4 = "198.51.100.9"  # AS64501 Example Residential ISP, DE
  DATACENTER_V6  = "2001:db8::5"   # AS64500, US
  UNKNOWN_V4     = "192.0.2.1"     # deliberately absent
end
