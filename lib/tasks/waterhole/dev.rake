namespace :waterhole do
  namespace :dev do
    # None of these should ever run against a real deployment, and every one of
    # them says so before it does anything.
    development_only = lambda do
      abort "Refusing outside development." unless Rails.env.local?
    end

    # What DnsAllowlist makes of a domain right now, shown the same way wherever
    # one of these tasks changes it.
    report = lambda do |domain|
      records = DevDns.records_for(domain)
      puts "Override: #{DevDns.describe(records)}"

      result = DnsAllowlist.call(domain)
      puts "Outcome:  #{result.outcome}"
      puts "Detail:   #{result.detail}"
      puts "Expected: #{DnsAllowlist.expected_value}"
    end

    desc "Print a sign-in link for a seeded moderator, development only: rake 'waterhole:dev:impersonate[avery]'"
    task :impersonate, [ :username ] => :environment do |_, args|
      development_only.call

      moderator = Moderator.find_by(username: args[:username]) || Moderator.first
      abort "No moderators. Run bin/rails db:seed first." if moderator.nil?

      token = Rails.application.message_verifier(:dev_sign_in)
        .generate({ moderator_id: moderator.id }, expires_in: 1.hour)
      puts "Open: #{Waterhole::Deployment.base_url}/dev/sign_in?token=#{token}"
      puts "Signs in as #{moderator.handle} for one hour. Development only."
    end

    # The record is the instance admin's half of the handshake, and in
    # development nobody has it: WATERHOLE_FAKE_DNS can only say "verified".
    # This says anything, so the refusal pages, the terms grace window and
    # revocation are all reachable from a laptop.
    desc "Show or override the DNS record observed for a domain: rake 'waterhole:dev:dns[some.example,terms_outdated]'"
    task :dns, %i[domain spec] => :environment do |_, args|
      development_only.call

      if args[:domain].blank?
        overrides = DevDns.all
        puts overrides.empty? ? "No overrides; every domain resolves normally." : "Overrides:"
        overrides.sort.each { |domain, records| puts format("  %-32s %s", domain, DevDns.describe(records)) }

        puts
        puts "Scenarios:"
        DevDns::SCENARIOS.each { |name, description| puts format("  %-15s %s", name, description) }
        puts
        puts "Or the records themselves, #{DevDns::SEPARATOR.inspect}-separated:"
        puts %(  rake 'waterhole:dev:dns[some.example,#{DnsAllowlist.expected_value}]')
        puts
        puts "Stored in #{DevDns.path.to_s.delete_prefix("#{Rails.root}/")}; deleting it clears them all."
        next
      end

      domain = args[:domain].downcase

      if args[:spec].present?
        records = DevDns.records_for_spec(args[:spec]) or
          abort "Unknown scenario #{args[:spec].inspect}. Run waterhole:dev:dns for the list."
        DevDns.set(domain, records)

        if args[:spec] == "terms_outdated" && LegalDocuments.digest.blank?
          puts "NOTE: this deployment publishes no legal documents, so the terms gate is"
          puts "      inactive and this record still verifies. Run waterhole:legal:install first."
        end
      end

      report.call(domain)
      puts
      puts "The hourly job will apply this on its own; waterhole:dev:verify applies it now."
    end

    desc "Drop a DNS override, or all of them: rake 'waterhole:dev:dns_clear[some.example]'"
    task :dns_clear, [ :domain ] => :environment do |_, args|
      development_only.call

      if args[:domain].blank?
        count = DevDns.clear_all
        puts "Cleared #{count} #{count == 1 ? "override" : "overrides"}."
        next
      end

      domain = args[:domain].downcase
      puts DevDns.clear(domain) ? "Cleared the override for #{domain}." : "No override for #{domain}."
      report.call(domain)
    end

    # Revocation takes Instances::ApplyVerification::FAILURES_BEFORE_REVOCATION
    # consecutive failures, and the job that counts them runs hourly -- so
    # watching an instance lose access otherwise means waiting three hours.
    desc "Re-verify instances against DNS now, instead of waiting for the hourly job: rake 'waterhole:dev:verify[some.example]'"
    task :verify, [ :domain ] => :environment do |_, args|
      development_only.call

      instances =
        if args[:domain].blank?
          Instance.order(:domain).to_a
        else
          instance = Instance.find_by(domain: args[:domain].downcase)
          abort "No instance #{args[:domain]}. It appears here after its first sign-in." if instance.nil?
          [ instance ]
        end

      instances.each do |instance|
        VerifyInstanceJob.perform_now(instance)
        instance.reload
        strikes = instance.consecutive_verification_failures
        note =
          if strikes.zero?        then instance.verification_detail
          elsif instance.revoked? then "#{strikes} strikes"
          else "#{strikes}/#{VerifyInstanceJob::FAILURES_BEFORE_REVOCATION} strikes"
          end

        puts format("  %-32s %-15s %s", instance.domain, instance.status, note)
      end
    end
  end
end
