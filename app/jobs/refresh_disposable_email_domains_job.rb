require "faraday/follow_redirects"

# Refreshes the disposable email domain list daily, the cadence upstream
# changes it at. A failed refresh keeps the list already in place -- the last
# download, or the vendored copy -- and records why, as RefreshIpDatabasesJob
# does: stale data beats no data.
#
# Then, whether or not the download worked, the pending queue is reconciled
# with the list in use: every pending request whose disposable_email flag the
# list would add, remove or word differently is recomputed. Otherwise a newly
# listed domain would flag only the requests that happen to be touched next,
# and two identical pending requests could disagree. Unconditional on purpose:
# it is cheap, so a run that died halfway, a new vendored copy on a machine
# that cannot download, or a download replacing the vendored copy all settle
# on the next run without anything having to notice the change.
class RefreshDisposableEmailDomainsJob < ApplicationJob
  queue_as :default

  LIST = DomainLists::DisposableEmailDomains

  def perform
    install
    reconcile_pending_requests
  end

  private

  def install
    directory = LIST.directory
    FileUtils.mkdir_p(directory)
    # Unique per run, not per process: two runs can share a worker process.
    temporary = directory.join("#{LIST::NAME}.txt.download-#{SecureRandom.hex(4)}")

    response = http.get(LIST::SOURCE_URL)
    raise "HTTP #{response.status} downloading #{LIST::SOURCE_URL}" unless response.success?

    domains = LIST.parse(response.body)
    temporary.write(domains.join("\n") + "\n")
    # Atomic within a filesystem, so no reader ever sees a partial list.
    File.rename(temporary, LIST.path)
    LIST.write_metadata(
      fetched_at: Time.current.iso8601, domain_count: domains.size,
      sha256: Digest::SHA256.hexdigest(response.body), error: nil
    )

    Rails.logger.info("[waterhole] refreshed #{LIST::NAME} (#{domains.size} domains)")
  rescue StandardError => e
    record_failure(e)
  ensure
    FileUtils.rm_f(temporary.to_s) if temporary
  end

  # Only where the flag would change, details included: the listed parent
  # named in the flag can change while the address stays listed. Checking a
  # domain is microseconds; a recompute runs every rule.
  def reconcile_pending_requests
    stored = Flag.where(rule: Flags::DisposableEmail.rule_name, registration_request_id: RegistrationRequest.pending.select(:id))
      .pluck(:registration_request_id, :details).to_h
    affected = RegistrationRequest.pending.pluck(:id, :email_domain).filter_map do |id, domain|
      id if Flags::DisposableEmail.details_for(domain).as_json != stored[id]
    end

    RegistrationRequest.where(id: affected).includes(:instance).find_each(&:recompute_flags!)
  end

  def record_failure(error)
    Rails.logger.error("[waterhole] #{LIST::NAME} refresh failed: #{error.class}: #{error.message}")
    # The network failing is tomorrow's retry. A list that stopped parsing
    # needs a person.
    Rails.error.report(error, handled: true, context: { list: LIST::NAME }) unless error.is_a?(Faraday::Error)

    LIST.write_metadata(LIST.metadata.merge(
      "error" => "#{error.class}: #{error.message}", "failed_at" => Time.current.iso8601
    ))
  rescue SystemCallError => e
    # The directory itself is the problem (unwritable, missing parent): the log
    # line above is all there can be.
    Rails.logger.error("[waterhole] #{LIST::NAME} could not record the failure: #{e.message}")
  end

  def http
    Faraday.new do |f|
      f.response :follow_redirects, limit: 5
      f.options.open_timeout = 10
      f.options.timeout = 60
      SecureAdapter.use(f)
    end
  end
end
