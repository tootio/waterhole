namespace :waterhole do
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
        puts format("  %-18s %-13s %s", document.slug, source, document.short_digest || LegalDocuments::UNPUBLISHED)
      end
      puts

      if LegalDocuments.digest.blank?
        puts "No documents published, so accepted= is omitted and the terms gate is INACTIVE."
        puts "Run waterhole:legal:install to start from the templates."
      else
        puts "accepted: #{LegalDocuments.digest}"
        puts "Record:       #{DnsAllowlist.expected_record("<instance domain>")}"
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
        changed = instance.outdated_documents.map(&:slug).join(", ")
        puts format("  %-32s %-24s changed: %s", instance.domain, state, changed)
      end
    end
  end
end
