namespace :waterhole do
  namespace :stats do
    # The hourly job only counts its recent window. This reaches back to the
    # oldest request still here, for a deployment that already has history when
    # the stats arrive. Requests purged before then are not counted anywhere.
    desc "Count every request still stored into the hourly registration stats"
    task backfill: :environment do
      since = RegistrationRequest.minimum(:signed_up_at)
      abort "No registration requests to count." unless since

      RollUpRegistrationStatsJob.perform_now(since:)
      puts "Counted signups since #{since.utc.iso8601} into #{RegistrationStat.count} hourly rows."
    end
  end
end
