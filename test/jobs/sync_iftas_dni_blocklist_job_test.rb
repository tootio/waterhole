require "test_helper"

class SyncIftasDniBlocklistJobTest < ActiveSupport::TestCase
  CSV_URL = Blocklists::IftasDni::DEFAULT_CSV_URL

  # Every real response carries the canary row (see
  # Blocklists::IftasDni::CANARY_TAG), so it's added by default; pass
  # canary: false to test what happens when a response doesn't have one.
  def stub_csv(rows, canary: true)
    header = "#domain,#severity,#reject_media,#reject_reports,#public_comment,#obfuscate"
    canary_row = csv_row("dni.invalid", comment: "iftas:canary")
    body = ([ header ] + rows + (canary ? [ canary_row ] : [])).join("\n")
    stub_request(:get, CSV_URL).to_return(status: 200, body:)
  end

  def csv_row(domain, severity: "suspend", comment: "iftas:hate-speech")
    %("#{domain}","#{severity}","FALSE","FALSE","#{comment}","TRUE")
  end

  # Faraday follows a redirect on its own, so nothing about the sync depends
  # on the sheet returning more than 20 well-formed rows -- pad with distinct
  # domains to clear Blocklists::IftasDni::MINIMUM_ROWS.
  def padding_rows(count, prefix: "pad")
    Array.new(count) { |i| csv_row("#{prefix}#{i}.example") }
  end

  test "adds newly listed domains as blocked, sourced from iftas_dni, with subdomains included" do
    stub_csv(padding_rows(20) + [ csv_row("new-spam.example", comment: "iftas:csam") ])

    SyncIftasDniBlocklistJob.perform_now

    policy = DomainPolicy.find_by(domain: "new-spam.example")
    assert policy.blocked?
    assert policy.iftas_dni?
    assert policy.include_subdomains?
    assert_equal "iftas:csam", policy.reason
  end

  # A suspend on the DNI list covers the whole network, not just the bare
  # domain, so a row that predates this behaviour (or was somehow reset) gets
  # corrected on the next sync rather than staying narrower than intended.
  test "backfills include_subdomains on an existing iftas_dni row that lacks it" do
    policy = domain_policies(:blocked_synced)
    policy.update!(include_subdomains: false)
    stub_csv(padding_rows(20) + [ csv_row(policy.domain, comment: policy.reason) ])

    SyncIftasDniBlocklistJob.perform_now

    assert policy.reload.include_subdomains?
  end

  test "updates the reason on an existing iftas_dni row when it changes" do
    policy = domain_policies(:blocked_synced)
    stub_csv(padding_rows(20) + [ csv_row(policy.domain, comment: "iftas:new-reason") ])

    SyncIftasDniBlocklistJob.perform_now

    assert_equal "iftas:new-reason", policy.reload.reason
  end

  test "removes an iftas_dni row no longer on the list" do
    policy = domain_policies(:blocked_synced)
    stub_csv(padding_rows(20))

    SyncIftasDniBlocklistJob.perform_now

    assert_not DomainPolicy.exists?(policy.id)
  end

  test "a manual row is left alone even if the list would add, change, or drop it" do
    manual = domain_policies(:blocked_spam)
    stub_csv(padding_rows(20) + [ csv_row(manual.domain, comment: "iftas:different-reason") ])

    SyncIftasDniBlocklistJob.perform_now

    manual.reload
    assert manual.manual?
    assert_equal "Repeatedly used to farm accounts.", manual.reason,
      "sync must never overwrite a hand-added policy's reason"
  end

  test "a manual row not on the list is never removed by sync" do
    manual = domain_policies(:blocked_spam)
    stub_csv(padding_rows(20))

    SyncIftasDniBlocklistJob.perform_now

    assert DomainPolicy.exists?(manual.id)
  end

  test "the iftas:canary sentinel row is skipped" do
    stub_csv(padding_rows(20))

    SyncIftasDniBlocklistJob.perform_now

    assert_not DomainPolicy.exists?(domain: "dni.invalid")
  end

  # The canary's whole job is to catch a response that looks fine otherwise --
  # this is what a stale cache, the wrong sheet, or an upstream format change
  # would look like, and MINIMUM_ROWS alone would wave it through.
  test "rejects the sync when the canary row is missing, even with plenty of other rows" do
    before = DomainPolicy.order(:id).pluck(:id, :domain, :kind, :source, :reason)
    stub_csv(padding_rows(20), canary: false)

    SyncIftasDniBlocklistJob.perform_now

    assert_equal before, DomainPolicy.order(:id).pluck(:id, :domain, :kind, :source, :reason)
  end

  test "a non-suspend severity is skipped" do
    stub_csv(padding_rows(20) + [ csv_row("silenced.example", severity: "silence") ])

    SyncIftasDniBlocklistJob.perform_now

    assert_not DomainPolicy.exists?(domain: "silenced.example")
  end

  # Mirrors RefreshIpDatabasesJob: a data problem (as opposed to a network
  # blip) is reported and logged rather than raised, so it doesn't retry
  # forever -- but the point of the test is that nothing gets written.
  test "a suspiciously short response is not treated as an empty blocklist" do
    before = DomainPolicy.order(:id).pluck(:id, :domain, :kind, :source, :reason)
    stub_csv(padding_rows(5))

    SyncIftasDniBlocklistJob.perform_now

    assert_equal before, DomainPolicy.order(:id).pluck(:id, :domain, :kind, :source, :reason)
  end

  test "running twice in a row is idempotent" do
    stub_csv(padding_rows(20) + [ csv_row("steady.example") ])

    SyncIftasDniBlocklistJob.perform_now
    before = DomainPolicy.iftas_dni.pluck(:domain, :reason, :kind).sort

    SyncIftasDniBlocklistJob.perform_now
    after = DomainPolicy.iftas_dni.pluck(:domain, :reason, :kind).sort

    assert_equal before, after
  end
end
