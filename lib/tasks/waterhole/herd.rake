namespace :waterhole do
  # Who may bring a herd here, and what's known about the herds already down:
  # the domain policy that gates admission, and the Instance records it acts on.
  namespace :herd do
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
          puts format("  %-8s %-9s %-32s %s", policy.kind, policy.source, policy.domain + suffix, policy.reason)
        end
      end
    end

    desc "Refuse to serve a domain: rake 'waterhole:herd:block[spam.example,reason]'"
    task :block, %i[domain reason] => :environment do |_, args|
      abort "usage: rake 'waterhole:herd:block[domain,reason]'" if args[:domain].blank?

      # Explicit operator action, so this always claims the row as manual, even
      # if it was previously synced from a shared list: from here on nothing
      # else may touch it. See waterhole:blocklists:sync_iftas_dni.
      policy = DomainPolicy.find_or_initialize_by(domain: args[:domain].downcase)
      policy.update!(kind: "blocked", source: "manual", reason: args[:reason])

      # Blocking is meant to take effect now, not at the next hourly check.
      if (instance = Instance.find_by(domain: policy.domain))
        instance.revoke!(reason: "Blocked by the operator of this Waterhole.", status: :blocked)
        puts "Blocked #{policy.domain} and signed out #{instance.moderators.count} moderator(s)."
      else
        puts "Blocked #{policy.domain}."
      end
    end

    desc "Allow a domain: rake 'waterhole:herd:allow[good.example]'"
    task :allow, [ :domain ] => :environment do |_, args|
      abort "usage: rake 'waterhole:herd:allow[domain]'" if args[:domain].blank?

      # Same manual claim as waterhole:herd:block, for the same reason.
      policy = DomainPolicy.find_or_initialize_by(domain: args[:domain].downcase)
      policy.update!(kind: "allowed", source: "manual", reason: nil)
      Instance.find_by(domain: policy.domain)&.update(status: "unverified")
      puts "Allowed #{policy.domain}. (Mode is #{Waterhole::Deployment.policy_mode}.)"
    end

    desc "Remove a manually-set domain policy: rake 'waterhole:herd:unset[some.example]'"
    task :unset, [ :domain ] => :environment do |_, args|
      domain = args[:domain].to_s.downcase
      policy = DomainPolicy.find_by(domain: domain)

      if policy.nil?
        puts "No policy for #{domain}."
      elsif policy.iftas_dni?
        # Destroying it here would only last until the next sync reimports it
        # from the list. waterhole:herd:allow claims the domain as manual,
        # which is what actually keeps sync's hands off it going forward.
        puts "#{domain} is blocked by the IFTAS DNI sync, not set by hand -- unsetting it would just " \
          "be reimported on the next sync. Run rake 'waterhole:herd:allow[#{domain}]' instead."
      else
        policy.destroy!
        puts "Removed policy for #{domain}."
      end
    end

    # Cross-instance signals need two keys. The instance admin's consent is
    # `signals=on` in their DNS record, read on every check; this task is the
    # operator's, and only approves or withdraws. Approving an instance whose
    # record does not opt in does nothing until it does.
    desc "Show or set cross-instance signal approval: rake 'waterhole:herd:signals[domain,approve|withdraw]'"
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
        abort "usage: rake 'waterhole:herd:signals[domain,approve|withdraw]'"
      end
    end

    desc "Check a domain's DNS authorisation now: rake 'waterhole:herd:check[some.example]'"
    task :check, [ :domain ] => :environment do |_, args|
      result = Admission.call(args[:domain].to_s)
      puts "Expected: #{DnsAllowlist.expected_record(args[:domain])}"
      puts "Outcome:  #{result.outcome}"
      puts "Message:  #{result.message}" if result.message
      puts "Observed: #{result.dns.records.presence&.join(" | ") || "(none)"}" if result.dns
    end
  end
end
