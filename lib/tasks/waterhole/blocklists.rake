namespace :waterhole do
  namespace :blocklists do
    desc "Sync the blocklist with the IFTAS DNI list now, regardless of WATERHOLE_IFTAS_DNI_SYNC"
    task sync_iftas_dni: :environment do
      SyncIftasDniBlocklistJob.perform_now
      puts "Synced. #{DomainPolicy.iftas_dni.count} domain(s) currently blocked via IFTAS DNI."
    end
  end
end
