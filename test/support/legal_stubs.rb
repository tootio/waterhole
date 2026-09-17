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

  # A TXT record naming this deployment, optionally accepting a given digest.
  def dns_record(accepted_tos: :none, host: Waterhole::Deployment.host)
    value = "v=waterhole1; host=#{host}"
    value += "; accepted_tos=#{accepted_tos}" unless accepted_tos == :none
    dns_records([ value ])
  end
end
