namespace :waterhole do
  namespace :domain_lists do
    desc "Download the disposable email domain list now, and show its status"
    task refresh_disposable_email_domains: :environment do
      RefreshDisposableEmailDomainsJob.perform_now
      Rake::Task["waterhole:domain_lists:status"].invoke
    end

    desc "Show which disposable email domain list is in use and how fresh it is"
    task status: :environment do
      list = DomainLists::DisposableEmailDomains
      fetched_at = list.fetched_at
      state =
        if !list.installed? then "NOT DOWNLOADED (using the vendored copy)"
        elsif list.stale?   then "STALE (fetched #{fetched_at&.to_fs(:db) || "never"})"
        else "ok (fetched #{fetched_at.to_fs(:db)})"
        end

      puts "  #{list::NAME}: #{state}, #{list.domains.size} domains"
      error = list.metadata["error"]
      puts "  last error: #{error}" if error.present?
    end
  end
end
