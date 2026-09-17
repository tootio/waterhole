namespace :waterhole do
  # Deliberately does not load the app: a production boot refuses to start
  # until these exist, so generating them must not need a booted app.
  desc "Print freshly generated secrets for .env.production"
  task :secrets do
    require "securerandom"

    puts <<~ENV
      # Generated #{Time.now.utc.iso8601}. Keep these safe and keep them stable:
      # losing the encryption keys makes stored tokens and emails unreadable.
      SECRET_KEY_BASE=#{SecureRandom.hex(64)}
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=#{SecureRandom.alphanumeric(32)}
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=#{SecureRandom.alphanumeric(32)}
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=#{SecureRandom.alphanumeric(32)}
      WATERHOLE_EMAIL_HMAC_KEY=#{SecureRandom.hex(32)}
    ENV
  end

  desc "Show this deployment's admission policy"
  task policy: :environment do
    puts "Host:        #{Waterhole::Deployment.host}"
    puts "Policy mode: #{Waterhole::Deployment.policy_mode}"
    puts
    if DomainPolicy.none?
      puts "No domain policies. Every domain that publishes the DNS record may connect."
    else
      DomainPolicy.order(:kind, :domain).each do |policy|
        suffix = policy.include_subdomains? ? " (+subdomains)" : ""
        puts format("  %-8s %-32s %s", policy.kind, policy.domain + suffix, policy.reason)
      end
    end
  end

  desc "Refuse to serve a domain: rake 'waterhole:block[spam.example,reason]'"
  task :block, %i[domain reason] => :environment do |_, args|
    abort "usage: rake 'waterhole:block[domain,reason]'" if args[:domain].blank?

    policy = DomainPolicy.find_or_initialize_by(domain: args[:domain].downcase)
    policy.update!(kind: "blocked", reason: args[:reason])

    # Blocking is meant to take effect now, not at the next hourly check.
    if (instance = Instance.find_by(domain: policy.domain))
      instance.revoke!(reason: "Blocked by the operator of this Waterhole.", status: :blocked)
      puts "Blocked #{policy.domain} and signed out #{instance.moderators.count} moderator(s)."
    else
      puts "Blocked #{policy.domain}."
    end
  end

  desc "Allow a domain: rake 'waterhole:allow[good.example]'"
  task :allow, [ :domain ] => :environment do |_, args|
    abort "usage: rake 'waterhole:allow[domain]'" if args[:domain].blank?

    policy = DomainPolicy.find_or_initialize_by(domain: args[:domain].downcase)
    policy.update!(kind: "allowed", reason: nil)
    Instance.find_by(domain: policy.domain)&.update(status: "unverified")
    puts "Allowed #{policy.domain}. (Mode is #{Waterhole::Deployment.policy_mode}.)"
  end

  desc "Remove a domain policy: rake 'waterhole:unset[some.example]'"
  task :unset, [ :domain ] => :environment do |_, args|
    count = DomainPolicy.where(domain: args[:domain].to_s.downcase).destroy_all.size
    puts count.positive? ? "Removed policy for #{args[:domain]}." : "No policy for #{args[:domain]}."
  end

  # Cross-instance signals need two keys. The instance admin's consent is
  # `signals=on` in their DNS record, read on every check; this task is the
  # operator's, and only approves or withdraws. Approving an instance whose
  # record does not opt in does nothing until it does.
  desc "Show or set cross-instance signal approval: rake 'waterhole:signals[domain,approve|withdraw]'"
  task :signals, %i[domain action] => :environment do |_, args|
    describe = lambda do |instance|
      state = instance.participating? ? "participating" : "off"
      reasons = []
      reasons << "record does not opt in" unless instance.signals_opted_in?
      reasons << "not approved" unless instance.signals_approved?
      reasons << "inactive: #{instance.status}" unless instance.admitted?
      format("  %-32s %s%s", instance.domain, state, reasons.any? ? " (#{reasons.join(", ")})" : "")
    end

    if args[:domain].blank?
      instances = Instance.order(:domain)
      puts "No instances yet." if instances.none?
      instances.each { puts describe.(it) }
      next
    end

    instance = Instance.find_by(domain: args[:domain].downcase) or
      abort "No instance #{args[:domain]}. It appears here after its first sign-in."

    case args[:action]
    when nil
      puts describe.(instance)
    when "approve", "withdraw"
      instance.update!(signals_approved: args[:action] == "approve")
      # The Instance hook queues the sweep, so every other instance's flags
      # follow within minutes, once the job worker picks it up.
      puts describe.(instance)
      if instance.signals_approved? && !instance.signals_opted_in?
        puts "Approved, but #{instance.domain}'s DNS record does not opt in yet. It needs:"
        puts "  #{DnsAllowlist.expected_record(instance.domain, signals: true)}"
      end
    else
      abort "usage: rake 'waterhole:signals[domain,approve|withdraw]'"
    end
  end

  desc "Check a domain's DNS authorisation now: rake 'waterhole:check[some.example]'"
  task :check, [ :domain ] => :environment do |_, args|
    result = Admission.call(args[:domain].to_s)
    puts "Expected: #{DnsAllowlist.expected_record(args[:domain])}"
    puts "Outcome:  #{result.outcome}"
    puts "Message:  #{result.message}" if result.message
    puts "Observed: #{result.dns.records.presence&.join(" | ") || "(none)"}" if result.dns
  end

  namespace :mmdb do
    desc "Download and verify the IP geolocation databases now"
    task refresh: :environment do
      RefreshIpDatabasesJob.perform_now
      Rake::Task["waterhole:mmdb:status"].invoke
    end

    desc "Show whether the IP databases are installed and how fresh they are"
    task status: :environment do
      puts "Directory: #{Ip::Databases.directory}"

      Ip::Databases.status.each do |name, info|
        state =
          if !info[:installed] then "NOT INSTALLED"
          elsif info[:stale]   then "STALE (fetched #{info[:fetched_at]&.to_fs(:db) || "never"})"
          else "ok (fetched #{info[:fetched_at].to_fs(:db)})"
          end

        puts format("  %-16s %s", name, state)
        puts "                   last error: #{info[:error]}" if info[:error].present?
      end

      puts
      puts "Run waterhole:mmdb:refresh to fetch them." unless Ip::Databases.ready?
    end

    desc "Print the raw database record for an address: rake 'waterhole:mmdb:probe[1.2.3.4]'"
    task :probe, [ :address ] => :environment do |_, args|
      address = args[:address].presence or abort "usage: rake 'waterhole:mmdb:probe[address]'"
      result = Ip::Lookup.call(address)

      if result.nil?
        puts "#{address}: skipped (private, malformed, or lookup unavailable)"
      else
        puts "#{address}: country=#{result.country.inspect} asn=#{result.asn.inspect} org=#{result.asn_org.inspect}"
      end
    end

    desc "Which ASNs are signing up, and how they were decided"
    task :asn_report, [ :days ] => :environment do |_, args|
      since = Integer(args[:days] || 90).days.ago

      RegistrationRequest.where(signed_up_at: since..).where.not(ip_asn: nil)
        .group(:ip_asn, :ip_asn_org, :status).count
        .group_by { |(asn, org, _), _| [ asn, org ] }
        .sort_by { |_, rows| -rows.sum { it.last } }
        .first(25)
        .each do |(asn, org), rows|
          breakdown = rows.map { |(_, _, status), count| "#{status}=#{count}" }.join(" ")
          puts format("  AS%-8s %-34s %s", asn, org.to_s[0, 34], breakdown)
        end
    end
  end

  namespace :legal do
    desc "Copy the legal templates from config/legal for any document not yet written"
    task install: :environment do
      installed = LegalDocuments.install_examples

      if installed.empty?
        puts "Nothing to install; every document already exists."
      else
        puts "Installed templates for: #{installed.join(", ")}"
        puts "Edit #{LegalDocuments.directory}/*.md, then run waterhole:legal:digest."
      end
    end

    desc "Show the documents, their digests, and the DNS record instances must publish"
    task digest: :environment do
      LegalDocuments.all.each do |document|
        source = document.published? ? "published" : "EXAMPLE ONLY"
        puts format("  %-18s %-13s %s", document.slug, source, document.digest || "-")
      end
      puts

      if LegalDocuments.digest.blank?
        puts "No documents published, so accepted_tos is omitted and the terms gate is INACTIVE."
        puts "Run waterhole:legal:install to start from the templates."
      else
        puts "Combined digest: #{LegalDocuments.digest}"
        puts "Record:          #{DnsAllowlist.expected_record("<instance domain>")}"
      end
    end

    desc "Who has accepted the current documents, and who is on the clock"
    task status: :environment do
      if LegalDocuments.digest.blank?
        puts "Terms gate inactive: this deployment publishes no legal documents."
        next
      end

      current = Instance.where(accepted_terms_digest: LegalDocuments.digest)
      puts "Accepted current documents: #{current.count}"

      Instance.where(status: "terms_outdated").order(:terms_grace_until).each do |instance|
        state = instance.terms_grace_active? ? "until #{instance.terms_grace_until.to_fs(:db)}" : "OVERDUE"
        puts format("  %-32s %s", instance.domain, state)
      end
    end
  end

  desc "Dev only. Print a sign-in link for a seeded moderator: rake 'waterhole:impersonate[avery]'"
  task :impersonate, [ :username ] => :environment do |_, args|
    abort "Refusing outside development." unless Rails.env.local?

    moderator = Moderator.find_by(username: args[:username]) || Moderator.first
    abort "No moderators. Run bin/rails db:seed first." if moderator.nil?

    token = Rails.application.message_verifier(:dev_sign_in)
      .generate({ moderator_id: moderator.id }, expires_in: 1.hour)
    puts "Open: #{Waterhole::Deployment.base_url}/dev/sign_in?token=#{token}"
    puts "Signs in as #{moderator.handle} for one hour. Development only."
  end
end
