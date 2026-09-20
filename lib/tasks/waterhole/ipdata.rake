namespace :waterhole do
  namespace :ipdata do
    desc "Download and verify all IP data now: geolocation databases, Private Relay and Tor lists"
    task refresh: :environment do
      RefreshIpDatabasesJob.perform_now(names: Ip::Databases::NAMES + RefreshIpDatabasesJob::RANGE_LISTS.keys)
      Rake::Task["waterhole:ipdata:status"].invoke
    end

    desc "Show whether the IP data is installed and how fresh it is"
    task status: :environment do
      puts "Directory: #{Ip::Databases.directory}"

      Ip::Databases.status.each do |name, info|
        state =
          if !info[:installed] then "NOT INSTALLED"
          elsif info[:stale]   then "STALE (fetched #{info[:fetched_at]&.to_fs(:db) || "never"})"
          else "ok (fetched #{info[:fetched_at].to_fs(:db)})"
          end

        puts format("  %-22s %s", name, state)
        puts "                         last error: #{info[:error]}" if info[:error].present?
      end

      puts
      puts "Run waterhole:ipdata:refresh to fetch them." unless Ip::Databases.ready?
    end

    desc "Print the raw database record for an address: rake 'waterhole:ipdata:probe[1.2.3.4]'"
    task :probe, [ :address ] => :environment do |_, args|
      address = args[:address].presence or abort "usage: rake 'waterhole:ipdata:probe[address]'"
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
end
