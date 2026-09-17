require "test_helper"

class RegistrationRequests::EnrichmentTest < ActiveSupport::TestCase
  setup do
    @instance = instances(:alpha)
    @instance.update!(sync_moderator: moderators(:avery))
  end

  def payload_from(id, ip)
    payload = admin_account_payload(id:, username: "u#{id}")
    payload["ip"] = { "ip" => ip }
    payload["ips"] = []
    payload
  end

  test "sync records country and ASN for the signup address" do
    with_ip_databases do
      stub_pending_accounts(@instance, accounts: [ payload_from(7001, IpStubs::DATACENTER_V4) ])

      SyncInstanceJob.perform_now(@instance)

      record = @instance.registration_requests.find_by(mastodon_account_id: "7001")
      assert_equal "US", record.ip_country
      assert_equal 64500, record.ip_asn
      assert_equal "Example Hosting LLC", record.ip_asn_org
      assert record.ip_enriched_at.present?
    end
  end

  test "the datacenter flag follows from enrichment in the same pass" do
    with_ip_databases do
      stub_pending_accounts(@instance, accounts: [ payload_from(7002, IpStubs::DATACENTER_V4) ])

      SyncInstanceJob.perform_now(@instance)

      record = @instance.registration_requests.find_by(mastodon_account_id: "7002")
      assert record.flags.exists?(rule: "datacenter_asn"),
        "enrichment must happen before the changed? check that drives recompute"
    end
  end

  test "enrichment is not redone for an unchanged address" do
    with_ip_databases do
      record = registration_requests(:pending_alpha)
      record.update!(ip: IpStubs::RESIDENTIAL_V4)
      RegistrationRequests::Enrichment.apply(record)
      record.save!
      first = record.ip_enriched_at

      refute RegistrationRequests::Enrichment.needs_enrichment?(record.reload),
        "a re-sync should not redo the lookup for every unchanged row"
      assert_equal first.to_i, record.ip_enriched_at.to_i
    end
  end

  test "an address with no data is still stamped, so it is not retried forever" do
    with_ip_databases do
      record = registration_requests(:pending_alpha)
      record.ip = IpStubs::UNKNOWN_V4
      RegistrationRequests::Enrichment.apply(record)
      record.save!

      assert record.ip_enriched_at.present?,
        "stamped even with no data, so 'looked and found nothing' is not confused with 'never looked'"
      assert_nil record.ip_asn
      refute RegistrationRequests::Enrichment.needs_enrichment?(record.reload)
    end
  end

  # Enrichment is a convenience and must never be the reason a sync fails.
  test "sync succeeds with no databases installed" do
    Dir.mktmpdir do |dir|
      Ip::Databases.stub_directory(dir) do
        stub_pending_accounts(@instance, accounts: [ admin_account_payload(id: 7003) ])

        assert_nothing_raised { SyncInstanceJob.perform_now(@instance) }
        assert @instance.registration_requests.exists?(mastodon_account_id: "7003")
      end
    end
  end

  test "the purge clears the derived network columns with the address" do
    with_ip_databases do
      record = registration_requests(:rejected_alpha)
      record.update!(ip: IpStubs::DATACENTER_V4, resolved_at: 200.days.ago)
      RegistrationRequests::Enrichment.apply(record)
      record.save!
      assert record.reload.ip_asn.present?

      PurgeResolvedRequestPiiJob.perform_now

      record.reload
      assert_nil record.ip_asn
      assert_nil record.ip_country
      assert_nil record.ip_asn_org
      assert_nil record.ip_group, "the generated key follows the address to NULL"
    end
  end
end
