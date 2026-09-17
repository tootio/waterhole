require "tmpdir"

module LegalStubs
  # Points LegalDocuments at a tmpdir containing real documents, so the digest,
  # the DNS record and the verification transitions are all exercised against
  # actual files rather than a mocked digest.
  def with_legal_documents(**bodies)
    Dir.mktmpdir do |dir|
      defaults = {
        terms_of_service: "# Terms\n\nBe excellent to each other.\n",
        privacy_policy: "# Privacy\n\nWe keep what we must.\n",
        imprint: "# Imprint\n\nOperated by Someone.\n"
      }
      defaults.merge(bodies).each do |slug, body|
        File.write(File.join(dir, "#{slug}.md"), body) if body
      end

      LegalDocuments.stub_directory(dir) { yield dir }
    end
  end

  # The text of a TXT record naming this deployment, optionally accepting a
  # given digest and opting in to signals.
  def txt_record(accepted: :none, signals: false, host: Waterhole::Deployment.host)
    value = "v=waterhole1; host=#{host}"
    value += "; accepted=#{accepted}" unless accepted == :none
    value += "; signals=on" if signals
    value
  end

  # A resolver answering with that one record.
  def dns_record(**) = dns_records([ txt_record(**) ])

  # Runs the hourly DNS check for one instance against a stubbed answer.
  def verify_against(instance, resolver)
    DnsAllowlist.stub_resolver(resolver) { VerifyInstanceJob.perform_now(instance) }
    instance.reload
  end
end
