# Mirrors one instance's pending-registration queue.
#
# This is a FULL RECONCILE, not an incremental cursor. The pending list is a set
# that items LEAVE -- approved or rejected directly in Mastodon's own admin UI --
# and a forward-only since_id cursor can never observe a removal. The queue is
# small (tens to low hundreds), so every run walks the whole thing.
class SyncInstanceJob < ApplicationJob
  queue_as :default

  # Solid Queue runs the lowest number first (jobs default to 0), so when every
  # thread is busy, the broadcasts that tell moderators' browsers to refresh
  # jump ahead of queued syncs instead of waiting behind them. It does not
  # preempt a sync already running.
  queue_with_priority 10

  # One sync per instance at a time. A retry backing off, a slow run or a manual
  # "sync now" could otherwise overlap the next scheduled run, and two runs
  # walking one queue race on the same rows, the flag recomputes and the sync
  # token. Discard rather than block: a queued-up copy would only redo the run
  # that is already in progress, and the next tick comes soon enough.
  #
  # The duration is how long a lock survives a worker that died mid-run; a
  # healthy run releases it as soon as it finishes.
  limits_concurrency to: 1, key: ->(instance) { instance }, duration: 10.minutes, on_conflict: :discard

  # Individually verifying vanished rows costs one API call each; Mastodon allows
  # 300 requests per 5 minutes per account, so cap it and let the next run finish.
  VERIFICATION_CAP = 50

  retry_on Mastodon::ConnectionError, Mastodon::ServerError,
    wait: :polynomially_longer, attempts: 5
  retry_on Mastodon::RateLimited, attempts: 3,
    wait: ->(_job, error) { error.retry_after }

  def perform(instance)
    return unless instance.admitted?

    @instance = instance
    @client   = build_client or return
    @run      = instance.sync_runs.create!(status: "running", started_at: Time.current)

    seen_ids, walk_complete = walk_pending
    reconcile_departures(seen_ids) if walk_complete

    @run.update!(status: walk_complete ? "succeeded" : "failed", finished_at: Time.current)

    if walk_complete
      instance.update!(last_synced_at: Time.current, last_sync_error: nil, last_sync_error_at: nil)
    else
      # A partial run is not a successful sync, and saying otherwise
      # would hide a stuck instance behind a fresh timestamp.
      instance.update!(last_sync_error: @run.error_message, last_sync_error_at: Time.current)
    end
  rescue Mastodon::Unauthorized, Mastodon::Forbidden => e
    # The borrowed token is dead, or its owner no longer has the role to list
    # pending accounts. Either way it is no use to sync: invalidate it and hand
    # sync to someone else.
    @client_moderator&.invalidate_token!
    fail_run(e, "Sync token rejected by #{instance.domain}; rotated to another moderator.")
    raise
  rescue Mastodon::Error => e
    fail_run(e, e.message)
    raise
  rescue StandardError => e
    # A bug rather than Mastodon misbehaving. Without this the run stayed
    # "running" forever and the instance page showed no error at all.
    fail_run(e, "Sync crashed: #{e.class}: #{e.message}")
    raise
  end

  private

  attr_reader :instance, :client, :run

  def build_client
    @client_moderator = instance.sync_token_holder
    unless @client_moderator
      instance.update!(last_sync_error: "No moderator token available to sync with.",
        last_sync_error_at: Time.current)
      return nil
    end

    Mastodon::Client.new(base_url: instance.base_url, access_token: @client_moderator.access_token)
  end

  # Returns [seen_mastodon_ids, walk_completed_cleanly].
  #
  # A partial walk must not be mistaken for "these accounts are gone", so any
  # error here flips the flag and reconciliation is skipped entirely.
  def walk_pending
    seen  = []
    pages = 0

    begin
      pages = client.each_pending_account do |payload, page_number|
        pages = page_number
        seen << payload["id"].to_s
        upsert(payload)
      end
      [ seen, true ]
    # Unlike on approve/reject, a 403 on the pending list is unambiguous: this
    # token's owner may not see the queue.
    rescue Mastodon::Unauthorized, Mastodon::Forbidden
      raise
    rescue Mastodon::Error => e
      run.update!(error_message: "Walk failed after #{pages} page(s): #{e.message}")
      [ seen, false ]
    ensure
      mark_seen(seen)
      run.update!(pages_fetched: pages, records_seen: seen.size)
    end
  end

  # Stamped in bulk, outside the per-record save. Set through the model it made
  # every pending row "changed" on every run: an UPDATE, a flag recompute and a
  # refresh broadcast per row, every five minutes, to say nothing had happened.
  # update_all skips callbacks and updated_at on purpose. Runs for a partial
  # walk too: what it did see is still in the queue.
  def mark_seen(mastodon_ids)
    return if mastodon_ids.empty?

    instance.registration_requests
      .where(mastodon_account_id: mastodon_ids)
      .update_all(last_seen_in_queue_at: run.started_at)
  end

  def upsert(payload)
    attributes = RegistrationRequests::Mapper.call(payload)

    # Purged here, by a moderator or after retention: never import it again,
    # even while Mastodon still lists the account as pending.
    return if purged_ids.include?(attributes[:mastodon_account_id])

    record = instance.registration_requests
      .find_or_initialize_by(mastodon_account_id: attributes[:mastodon_account_id])
    created = record.new_record?

    record.assign_attributes(attributes)
    # Before the changed? check below, or an enrichment-only change would not
    # recompute the datacenter_asn flag.
    RegistrationRequests::Enrichment.apply(record)
    # A row that reappears in the pending list is pending again, whatever we
    # last believed.
    record.status = "pending" if record.resolved_upstream?
    changed = record.changed?
    # Skipped when nothing changed: a no-op save still runs the commit
    # callbacks, i.e. a refresh broadcast per pending row on every run.
    record.save! if changed

    # Deliberately find_or_initialize + save! rather than upsert_all: model
    # callbacks and flag recomputation depend on it, and at this volume the extra
    # writes are irrelevant. If this ever moves to upsert_all, flags and
    # broadcasts must be re-driven explicitly.
    # The other side of cross-instance matches is refreshed by the model
    # itself (RegistrationRequest#refresh_cross_instance_counterparts), so it
    # also happens for decisions and departures, not only here.
    record.recompute_flags! if created || changed

    run.increment!(:records_created) if created
    run.increment!(:records_updated) if changed && !created
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Rows we still think are pending but which no longer appear upstream. Don't
  # guess why -- ask, one at a time. No limit on how many may leave at once: a
  # short walk only produces rows that read back as still pending, and a
  # moderator clearing the whole queue in Mastodon is a normal thing to do.
  def reconcile_departures(seen_ids)
    departed = instance.registration_requests.pending
      .where.not(mastodon_account_id: seen_ids)
      .limit(VERIFICATION_CAP)

    resolved = departed.count { |request| verify_departure(request) }
    run.increment!(:records_resolved, resolved)
  end

  def verify_departure(request)
    account = client.admin_account(request.mastodon_account_id)

    if account["approved"]
      resolve(request, "approved_elsewhere")
    else
      false # still pending upstream: a pagination artefact, leave it alone
    end
  rescue Mastodon::NotFound
    # Rejection deletes the user -- but so does Mastodon's cleanup of accounts
    # that never confirmed their email.
    resolve(request, request.deleted_upstream_status)
  rescue Mastodon::Forbidden
    false
  end

  def resolve(request, status)
    request.update!(status:, resolved_at: Time.current)
    true
  end

  # Loaded once per run: one query instead of one per pending account.
  def purged_ids = @purged_ids ||= instance.purged_registrations.pluck(:mastodon_account_id).to_set

  def fail_run(error, message)
    run&.update(status: "failed", finished_at: Time.current, error_message: error.message)
    instance.update(last_sync_error: message, last_sync_error_at: Time.current)
  end
end
