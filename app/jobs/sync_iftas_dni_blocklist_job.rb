# Keeps the domain blocklist in step with the IFTAS DNI list: rows this job
# added are updated or removed to match, and rows it never touched (a
# `manual` source) are left alone no matter what the list says. See
# DomainPolicy#source and Blocklists::IftasDni.
class SyncIftasDniBlocklistJob < ApplicationJob
  queue_as :default

  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 3

  def perform
    entries = Blocklists::IftasDni.parse(fetch)

    if entries.size < Blocklists::IftasDni::MINIMUM_ROWS
      raise "only #{entries.size} rows parsed; keeping the existing blocklist"
    end

    added = updated = removed = skipped = 0

    # One transaction: a reader must never see the blocklist half-migrated
    # between the old and new list.
    DomainPolicy.transaction do
      entries.each do |entry|
        policy = DomainPolicy.find_by(domain: entry[:domain])

        if policy.nil?
          # A suspend on the DNI list means the whole network, not just the
          # bare domain: IFTAS entries block subdomains along with it.
          DomainPolicy.create!(domain: entry[:domain], kind: "blocked", include_subdomains: true,
            source: Blocklists::IftasDni::SOURCE, reason: entry[:reason])
          added += 1
        elsif policy.manual?
          skipped += 1
        elsif policy.kind != "blocked" || policy.reason != entry[:reason] || !policy.include_subdomains?
          policy.update!(kind: "blocked", reason: entry[:reason], include_subdomains: true)
          updated += 1
        end
      end

      domains = entries.map { it[:domain] }
      removed = DomainPolicy.iftas_dni.where.not(domain: domains).destroy_all.size
    end

    Rails.logger.info("[waterhole] iftas_dni sync: #{added} added, #{updated} updated, " \
      "#{removed} removed, #{skipped} manual row(s) left alone")
  rescue StandardError => e
    Rails.logger.error("[waterhole] iftas_dni sync failed: #{e.class}: #{e.message}")
    # A network hiccup is tomorrow's retry (see retry_on above). A parse
    # failure or a suspiciously short list needs a person to look.
    Rails.error.report(e, handled: true, context: { job: "SyncIftasDniBlocklistJob" }) unless e.is_a?(Faraday::Error)
    raise if e.is_a?(Faraday::Error)
  end

  private

  def fetch
    response = http.get(Waterhole::Deployment.iftas_dni_url)
    raise "HTTP #{response.status} fetching the IFTAS DNI list" unless response.success?

    response.body
  end

  def http
    @http ||= Faraday.new do |f|
      f.response :follow_redirects, limit: 5
      f.options.open_timeout = 10
      f.options.timeout = 30
      f.adapter Faraday.default_adapter
    end
  end
end
