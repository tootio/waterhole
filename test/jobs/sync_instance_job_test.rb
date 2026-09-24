require "test_helper"

class SyncInstanceJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @instance = instances(:alpha)
    @instance.update!(sync_moderator: moderators(:avery))
  end

  def pending_ids = @instance.registration_requests.pending.pluck(:mastodon_account_id)

  test "mirrors new requests" do
    stub_pending_accounts(@instance, accounts: [ admin_account_payload(id: 5000, username: "newcomer") ])

    assert_difference -> { @instance.registration_requests.count }, 1 do
      SyncInstanceJob.perform_now(@instance)
    end

    record = @instance.registration_requests.find_by(mastodon_account_id: "5000")
    assert_equal "newcomer", record.username
    assert_equal "198.51.100.5", record.ip.to_s
    assert record.flags_count >= 0
  end

  test "is idempotent: running twice creates one record" do
    stub_pending_accounts(@instance, accounts: [ admin_account_payload(id: 5000) ])

    SyncInstanceJob.perform_now(@instance)
    assert_no_difference -> { @instance.registration_requests.count } do
      SyncInstanceJob.perform_now(@instance)
    end
  end

  test "a request that vanished and reads back approved is marked approved elsewhere" do
    existing = registration_requests(:pending_alpha)
    # Only this one leaves the queue; the rest are still upstream. (If they all
    # vanished at once the mass-resolve guard would -- correctly -- refuse.)
    stub_pending_accounts(@instance, accounts: still_pending_payloads(except: existing))
    stub_admin_account(@instance, id: existing.mastodon_account_id,
      body: { "id" => existing.mastodon_account_id, "approved" => true })

    SyncInstanceJob.perform_now(@instance)

    assert_equal "approved_elsewhere", existing.reload.status
    assert existing.resolved_at.present?
  end

  test "a request that vanished and 404s is marked rejected elsewhere" do
    existing = registration_requests(:pending_alpha)
    stub_pending_accounts(@instance, accounts: still_pending_payloads(except: existing))
    stub_admin_account(@instance, id: existing.mastodon_account_id, status: 404,
      body: { "error" => "Record not found" })

    SyncInstanceJob.perform_now(@instance)

    assert_equal "rejected_elsewhere", existing.reload.status
  end

  # Mastodon deletes accounts that never confirm their email after 7 days, and
  # that 404 looks exactly like a rejection.
  test "an unconfirmed request that vanished after a week is marked expired, not rejected" do
    existing = registration_requests(:pending_alpha)
    existing.update_columns(confirmed: false, signed_up_at: 8.days.ago)
    stub_pending_accounts(@instance, accounts: still_pending_payloads(except: existing))
    stub_admin_account(@instance, id: existing.mastodon_account_id, status: 404,
      body: { "error" => "Record not found" })

    SyncInstanceJob.perform_now(@instance)

    assert_equal "expired", existing.reload.status
  end

  test "an unconfirmed request that vanished within the week can only have been rejected" do
    existing = registration_requests(:pending_alpha)
    existing.update_columns(confirmed: false, signed_up_at: 2.days.ago)
    stub_pending_accounts(@instance, accounts: still_pending_payloads(except: existing))
    stub_admin_account(@instance, id: existing.mastodon_account_id, status: 404,
      body: { "error" => "Record not found" })

    SyncInstanceJob.perform_now(@instance)

    assert_equal "rejected_elsewhere", existing.reload.status
  end

  test "a request missing from one page but still pending upstream is left alone" do
    existing = registration_requests(:pending_alpha)
    stub_pending_accounts(@instance, accounts: still_pending_payloads(except: existing))
    stub_admin_account(@instance, id: existing.mastodon_account_id,
      body: { "id" => existing.mastodon_account_id, "approved" => false })

    SyncInstanceJob.perform_now(@instance)

    assert_equal "pending", existing.reload.status,
      "a pagination artefact must not be mistaken for a decision"
  end

  # The dangerous failure mode: a half-finished walk looks exactly like "every
  # applicant was actioned upstream".
  test "a walk that fails part-way resolves nothing at all" do
    before = pending_ids.sort

    stub_request(:get, "#{@instance.base_url}/api/v2/admin/accounts")
      .with(query: hash_including({ "status" => "pending" }))
      .to_return(status: 500, body: { "error" => "boom" }.to_json,
        headers: { "Content-Type" => "application/json" })

    SyncInstanceJob.perform_now(@instance)

    assert_equal before, pending_ids.sort, "a partial walk must never resolve anything"
    assert_equal "failed", @instance.sync_runs.order(:started_at).last.status
    assert @instance.reload.last_sync_error.present?,
      "a failed walk must not look like a clean sync"
  end

  test "refuses to resolve more than half the queue in one pass" do
    stub_pending_accounts(@instance, accounts: [])
    # Every vanished row would read back as approved: plausible individually,
    # implausible all at once.
    @instance.registration_requests.pending.find_each do |request|
      stub_admin_account(@instance, id: request.mastodon_account_id,
        body: { "id" => request.mastodon_account_id, "approved" => true })
    end

    SyncInstanceJob.perform_now(@instance)

    assert_equal 0, @instance.registration_requests.where(status: "approved_elsewhere").count,
      "the circuit breaker should have refused the whole batch"
    assert_equal "failed", @instance.sync_runs.order(:started_at).last.status
  end

  test "a dead sync token is invalidated and sync rotates to another moderator" do
    stub_request(:get, "#{@instance.base_url}/api/v2/admin/accounts")
      .with(query: hash_including({ "status" => "pending" }))
      .to_return(status: 401, body: { "error" => "unauthorized" }.to_json,
        headers: { "Content-Type" => "application/json" })

    assert_raises(Mastodon::Unauthorized) { SyncInstanceJob.perform_now(@instance) }

    assert moderators(:avery).reload.token_invalidated_at.present?
    assert_equal moderators(:blake), @instance.reload.sync_moderator,
      "sync should carry on with someone else's token rather than stop dead"
  end

  test "a sync token whose owner lost the role is dropped and sync rotates" do
    stub_request(:get, "#{@instance.base_url}/api/v2/admin/accounts")
      .with(query: hash_including({ "status" => "pending" }))
      .to_return(status: 403, body: { "error" => "This action is not allowed" }.to_json,
        headers: { "Content-Type" => "application/json" })

    assert_raises(Mastodon::Forbidden) { SyncInstanceJob.perform_now(@instance) }

    assert moderators(:avery).reload.token_invalidated_at.present?
    assert_equal moderators(:blake), @instance.reload.sync_moderator
  end

  # Regression: only Mastodon errors used to close the run, so a bug left it
  # "running" forever with nothing on the instance page.
  test "an unexpected error fails the run and is recorded" do
    stub_pending_accounts(@instance, accounts: [ admin_account_payload(id: 9901) ])

    mapper = RegistrationRequests::Mapper.singleton_class
    mapper.alias_method :original_call, :call
    mapper.define_method(:call) { |_| raise TypeError, "boom" }
    begin
      assert_raises(TypeError) { SyncInstanceJob.perform_now(@instance) }
    ensure
      mapper.alias_method :call, :original_call
      mapper.remove_method :original_call
    end

    run = @instance.sync_runs.order(:started_at).last
    assert_equal "failed", run.status
    assert run.finished_at
    assert_match(/TypeError: boom/, @instance.reload.last_sync_error)
  end

  test "does nothing for an instance that is not admitted" do
    @instance.update!(status: "revoked")

    assert_no_difference -> { SyncRun.count } do
      SyncInstanceJob.perform_now(@instance)
    end
  end

  test "records a sync run with counts" do
    stub_pending_accounts(@instance,
      accounts: [ admin_account_payload(id: 5000) ] + still_pending_payloads)

    SyncInstanceJob.perform_now(@instance)

    run = @instance.sync_runs.order(:started_at).last
    assert_equal "succeeded", run.status
    assert_equal @instance.registration_requests.pending.count, run.records_seen
    assert run.finished_at.present?
  end

  test "stamps last_seen_in_queue_at on every request it sees, with the run's start time" do
    stub_pending_accounts(@instance,
      accounts: [ admin_account_payload(id: 5000) ] + still_pending_payloads)

    SyncInstanceJob.perform_now(@instance)

    run = @instance.sync_runs.order(:started_at).last
    seen = @instance.registration_requests.pending
    assert seen.any?
    assert seen.all? { it.last_seen_in_queue_at == run.started_at },
      "new and existing rows alike carry the run's start time"
  end

  test "does not stamp a request that was not in the queue" do
    gone = registration_requests(:pending_alpha)
    gone.update_columns(last_seen_in_queue_at: 1.day.ago)
    stamp = gone.reload.last_seen_in_queue_at
    stub_pending_accounts(@instance, accounts: still_pending_payloads(except: gone))
    stub_admin_account(@instance, id: gone.mastodon_account_id,
      body: { "id" => gone.mastodon_account_id, "approved" => false })

    SyncInstanceJob.perform_now(@instance)

    assert_equal stamp, gone.reload.last_seen_in_queue_at
  end

  # The point of stamping in bulk: a run that finds nothing new must not write,
  # recompute flags or tell open browsers to refresh, once per pending row.
  test "a second run over unchanged data rewrites nothing and broadcasts nothing" do
    payloads = still_pending_payloads
    stub_pending_accounts(@instance, accounts: payloads)
    SyncInstanceJob.perform_now(@instance) # settle enrichment and derived fields
    clear_enqueued_jobs

    before = @instance.registration_requests.pending.pluck(:id, :updated_at).to_h
    first_stamp = @instance.registration_requests.pending.pick(:last_seen_in_queue_at)

    travel 5.minutes do
      assert_no_enqueued_jobs do
        SyncInstanceJob.perform_now(@instance)
      end
    end

    after = @instance.registration_requests.pending.pluck(:id, :updated_at).to_h
    assert_equal before, after, "unchanged rows must not be saved"
    assert_operator @instance.registration_requests.pending.pick(:last_seen_in_queue_at), :>, first_stamp,
      "but they still count as seen"
    run = @instance.sync_runs.order(:started_at).last
    assert_equal 0, run.records_updated
  end

  test "a request whose upstream data changed is still saved and broadcast" do
    existing = registration_requests(:pending_alpha)
    payloads = still_pending_payloads
    stub_pending_accounts(@instance, accounts: payloads)
    SyncInstanceJob.perform_now(@instance)
    clear_enqueued_jobs

    changed = payloads.map do |payload|
      next payload unless payload["id"] == existing.mastodon_account_id

      payload.merge("invite_request" => "Something entirely different this time.")
    end
    stub_pending_accounts(@instance, accounts: changed)

    SyncInstanceJob.perform_now(@instance)

    streams = enqueued_jobs.select { it["job_class"] == "Turbo::Streams::BroadcastStreamJob" }
      .map { it["arguments"].first }.uniq
    assert_includes streams, existing.to_gid_param
    assert_equal [ existing.to_gid_param, "#{@instance.to_gid_param}:registration_requests" ].sort, streams.sort,
      "only the changed request and the instance's queue are told to refresh"
    assert_equal "Something entirely different this time.", existing.reload.invite_request
  end

  test "syncs of one instance share a concurrency key, syncs of different instances do not" do
    alpha, beta = instances(:alpha), instances(:beta)

    assert_equal SyncInstanceJob.new(alpha).concurrency_key, SyncInstanceJob.new(alpha).concurrency_key
    assert_not_equal SyncInstanceJob.new(alpha).concurrency_key, SyncInstanceJob.new(beta).concurrency_key
  end

  # Solid Queue enforces the limit, and the test adapter ignores it, so enqueue
  # through the real adapter. Called directly rather than by swapping the job
  # class's adapter, which would leave that class pinned to it for every later
  # test in the process.
  test "a second sync of an instance that is already queued is discarded, other instances are not" do
    alpha, beta = instances(:alpha), instances(:beta)
    adapter = ActiveJob::QueueAdapters::SolidQueueAdapter.new

    assert_difference -> { SolidQueue::ReadyExecution.count }, 2 do
      [ alpha, alpha, beta ].each { adapter.enqueue(SyncInstanceJob.new(it)) }
    end
    assert_equal 0, SolidQueue::BlockedExecution.count, "discarded, not held back to run later"
    assert_equal 2, SolidQueue::Job.where(class_name: "SyncInstanceJob").count
  end

  # A refresh broadcast should never queue behind a sync. Solid Queue takes the
  # lowest priority number first, and the Turbo jobs carry no priority (0).
  test "syncs queue behind broadcasts" do
    adapter = ActiveJob::QueueAdapters::SolidQueueAdapter.new
    adapter.enqueue(SyncInstanceJob.new(instances(:alpha)))
    adapter.enqueue(Turbo::Streams::BroadcastStreamJob.new("stream", content: "<turbo-stream></turbo-stream>"))

    ready = SolidQueue::ReadyExecution.ordered.map { it.job.class_name }

    assert_equal [ "Turbo::Streams::BroadcastStreamJob", "SyncInstanceJob" ], ready
  end

  private

  # Payloads for the requests that are still in the upstream queue.
  def still_pending_payloads(except: nil)
    @instance.registration_requests.pending.reject { except && it.id == except.id }.map do |request|
      admin_account_payload(id: request.mastodon_account_id, username: request.username)
    end
  end
end
