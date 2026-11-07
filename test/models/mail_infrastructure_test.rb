require "test_helper"

class MailInfrastructureTest < ActiveSupport::TestCase
  def keys(domain, hosts = nil) = MailInfrastructure.classify(domain:, hosts:).map { it.provider.key }

  # What these domains' MX records really answered when this was written.
  test "services on their own mail servers are recognised by them" do
    assert_equal %w[test_mail], keys("mailslurp.com", %w[mxslurp.click mailslurp.mx])
    assert_equal %w[test_mail], keys("mailosaur.net", %w[smtp-in1.mailosaur.net smtp-in2.mailosaur.net])
    assert_equal %w[test_mail], keys("inbox.testmail.app", %w[mx.testmail.app])
    assert_equal %w[test_mail], keys("devinbox.io", %w[smtp.devinbox.io])
    assert_equal %w[ai_bot], keys("lumbox.co", %w[mx.lumbox.co])
    assert_equal %w[ai_bot], keys("trylumbox.com", %w[mx.lumbox.co])
    assert_equal %w[ai_bot], keys("robotomail.co", %w[mail.robotomail.com])
    assert_equal %w[ai_bot], keys("homingbox.net", %w[mx.agentboxd.com])
  end

  test "a custom domain on such a service's mail servers is recognised too" do
    assert_equal %w[test_mail], keys("example.org", %w[mxslurp.click])
    assert_equal %w[ai_bot], keys("example.org", %w[mx.agentboxd.com])
    assert_equal %w[ai_bot], keys("example.org", %w[mx.lumbox.co])
    assert_equal %w[ai_bot], keys("example.org", %w[mail.robotomail.com])
    assert_equal %w[ai_bot], keys("example.org", %w[mx.atomicmail.ai])
  end

  test "services whose MX says nothing are recognised by their domain" do
    assert_equal %w[ai_bot], keys("nylas.email", [])
    assert_equal %w[ai_bot], keys("nylas.email")
    assert_equal %w[test_mail cloudflare_email_routing],
      keys("zerodrop-sandbox.online", %w[route1.mx.cloudflare.net route2.mx.cloudflare.net])
    assert_equal "domain", MailInfrastructure.classify(domain: "agent.agentmail.to", hosts: nil).first.via
    assert_equal "agentmail.to", MailInfrastructure.classify(domain: "agent.agentmail.to", hosts: nil).first.matched
  end

  test "Amazon SES inbound alone is its own classification, in any region" do
    assert_equal %w[amazon_ses_inbound], keys("example.org", %w[inbound-smtp.us-east-1.amazonaws.com])
    assert_equal %w[amazon_ses_inbound], keys("example.org", %w[inbound-smtp.eu-central-1.amazonaws.com])
    assert_equal %w[amazon_ses_inbound], keys("example.org", %w[inbound-smtp.cn-north-1.amazonaws.com.cn])
  end

  test "a named service replaces the platform behind it" do
    assert_equal %w[ai_bot], keys("ilands.ai", %w[mxa.mailgun.org])
    assert_equal %w[ai_bot], keys("agentmail.to", %w[inbound-smtp.us-east-1.amazonaws.com])
    assert_equal %w[test_mail],
      keys("slurpinbox.com", %w[inbound-smtp.us-west-2.amazonaws.com mxslurp.click mailslurp.mx])
  end

  test "SES stays visible next to a provider that does not name the service" do
    assert_equal %w[amazon_ses_inbound google_workspace],
      keys("example.org", %w[inbound-smtp.us-east-1.amazonaws.com aspmx.l.google.com])
  end

  test "a workspace provider's customers are not all bots: Feishu only flags ilands.ai by name" do
    feishu = %w[mx1.feishu.cn mx2.feishu.cn mx3.feishu.cn]

    assert_equal %w[feishu_lark], keys("example.org", feishu)
    assert_equal %w[ai_bot feishu_lark], keys("ilands.ai", feishu)
  end

  test "big operators are told apart" do
    assert_equal %w[gmail], keys("gmail.com", %w[gmail-smtp-in.l.google.com alt1.gmail-smtp-in.l.google.com])
    assert_equal %w[google_workspace], keys("example.org", %w[aspmx.l.google.com alt1.aspmx.l.google.com])
    assert_equal %w[google_workspace], keys("example.org", %w[smtp.google.com])
    assert_equal %w[google_workspace], keys("example.org", %w[aspmx2.googlemail.com])
    assert_equal %w[office365], keys("example.org", %w[example-org.mail.protection.outlook.com])
    assert_equal %w[outlook_com], keys("outlook.com", %w[outlook-com.olc.protection.outlook.com])
    assert_equal %w[icloud_mail], keys("icloud.com", %w[mx01.mail.icloud.com])
    assert_equal %w[proton_mail], keys("proton.me", %w[mail.protonmail.ch mailsec.protonmail.ch])
    assert_equal %w[fastmail], keys("fastmail.com", %w[in1-smtp.messagingengine.com])
    assert_equal %w[zoho_mail], keys("example.org", %w[mx.zoho.com.au])
  end

  test "inbound email APIs are recognised" do
    %w[mx.sendgrid.net mxa.mailgun.org mxa.eu.mailgun.org inbound.postmarkapp.com].each do |host|
      assert_equal %w[inbound_email_api], keys("example.org", [ host ])
    end
  end

  test "disposable mail services are recognised by their shared MX or their own domains" do
    assert_equal %w[disposable_mail], keys("example.org", %w[tinyhost.shop])
    assert_equal %w[disposable_mail], keys("example.org", %w[in.mail.tm])
    assert_equal %w[disposable_mail], keys("10mail.org", %w[mx.10mail.org])
    assert_equal %w[disposable_mail], keys("hadjoy.com", %w[mail.hadjoy.com])
  end

  def match(domain, hosts, addresses) = MailInfrastructure.classify(domain:, hosts:, addresses:).sole

  test "a service's server gives it away when the name of its MX host doesn't" do
    found = match("new-throwaway.example", %w[mx.new-throwaway.example], %w[78.47.124.133])
    assert_equal "disposable_mail", found.provider.key
    assert_equal "ip", found.via
    assert_equal "78.47.124.133", found.matched

    assert_equal "ip", match("new-throwaway.example", %w[mx.new-throwaway.example], %w[2a01:4f8:c0c:944::6]).via
  end

  test "a neighbour on the same hoster's network is nothing" do
    assert_empty MailInfrastructure.classify(domain: "example.org", hosts: %w[mail.example.org],
      addresses: %w[78.47.124.134 2a01:4f8:c0c:944::7])
  end

  test "the domain and the MX host take precedence over the address, as stronger evidence" do
    assert_equal "domain", match("10mail.org", %w[mx.10mail.org], %w[78.47.124.133]).via
    assert_equal "mx", match("example.org", %w[tinyhost.shop], %w[144.91.107.45]).via
  end

  test "AI agent mailboxes on a mainstream provider are named as well" do
    assert_equal %w[ai_bot qq_mail], keys("agent.qq.com", %w[mx1.qq.com])
    assert_equal %w[qq_mail], keys("qq.com", %w[mx1.qq.com])
    assert_equal %w[ai_bot cloudflare_email_routing], keys("ilands.app", %w[route1.mx.cloudflare.net])
  end

  test "forwarding for one's own domain is only information" do
    assert_equal %w[domain_forwarding], keys("example.org", %w[mx1.improvmx.com mx2.improvmx.com])
    assert_equal %w[domain_forwarding], keys("example.org", %w[mx1.forwardemail.net])
    assert_equal %w[domain_forwarding], keys("example.org", %w[eforward1.registrar-servers.com])
    assert_equal %w[domain_forwarding], keys("example.org", %w[fwd1.porkbun.com])
    assert_empty keys("example.org", %w[mx1.privateemail.com mail.registrar-servers.com])
  end

  test "email aliases are only information" do
    assert_equal %w[email_alias], keys("passmail.com", %w[mx1.simplelogin.co])
    assert_equal %w[email_alias], keys("anonaddy.me", %w[mail2.anonaddy.me])
    assert_equal %w[email_alias], keys("aliasvault.net", %w[mail.aliasvault.net])
    assert_equal %w[email_alias], keys("duck.com", %w[smtp-inbound1.duck.com])
    assert_equal %w[email_alias], keys("addy.io", %w[mx1.addy.io])
    assert_equal %w[email_alias], keys("example.org", %w[mx1.alias.proton.me])
    assert_equal %w[email_alias], keys("privaterelay.appleid.com", %w[smtp1.privaterelay.appleid.com])
    assert_equal %w[email_alias], keys("jane.33mail.com", %w[smtpv2.ec2.33mail.com])
    assert_equal %w[email_alias], keys("example.org", %w[domains.33mail.com])
    assert_equal %w[email_alias], keys("4wrd.cc", %w[mx1.4wrd.cc])
    assert_equal %w[email_alias], keys("abinemail.com", %w[smtp7.opayq.com])
  end

  test "an alias service's own domains are known before any lookup" do
    %w[duck.com privaterelay.appleid.com addy.io spamgourmet.net burnermail.io].each do |domain|
      assert_equal %w[email_alias], keys(domain), domain
    end
  end

  test "an alias service behind Amazon SES is named instead of SES" do
    assert_equal %w[email_alias], keys("mozmail.com", %w[inbound-smtp.us-west-2.amazonaws.com])
    assert_equal %w[email_alias], keys("jane.mozmail.com", %w[inbound-smtp.us-west-2.amazonaws.com])
    assert_equal %w[email_alias], keys("relay.firefox.com", %w[inbound-smtp.us-west-2.amazonaws.com])
  end

  # Anyone can list an alias service's host as a spare MX, so it must not hide what
  # the domain's other hosts say.
  test "an alias MX host next to a platform hides nothing more severe" do
    assert_equal %w[inbound_email_api email_alias], keys("example.org", %w[mxa.mailgun.org mx1.simplelogin.co])
    assert_equal %w[amazon_ses_inbound email_alias],
      keys("example.org", %w[inbound-smtp.us-east-1.amazonaws.com mx1.addy.io])
  end

  test "more mailbox providers are told apart" do
    assert_equal %w[yahoo_mail], keys("yahoo.co.jp", %w[mx1.mail.yahoo.co.jp])
    assert_equal %w[tuta_mail], keys("tuta.io", %w[mail.tutanota.de])
    assert_equal %w[posteo], keys("posteo.com", %w[mx01.posteo.de])
    assert_equal %w[mailfence], keys("mf.me", %w[smtp1.mailfence.com])
    assert_equal %w[mailo], keys("netc.fr", %w[mx.mailo.com])
    assert_equal %w[seznam], keys("seznam.cz", %w[mx1.seznam.cz])
    assert_equal %w[t_online], keys("t-online.de", %w[mx00.t-online.de])
    assert_equal %w[vivaldi_mail], keys("vivaldi.net", %w[mxi-1.vivaldi.net])
    assert_equal %w[onion_mail], keys("onionmail.com", %w[mail.onionmail.com])
  end

  test "Japanese carriers and internet providers share one classification" do
    %w[mfsmax.docomo.ne.jp msv.softbank.ne.jp msv.softbank.jp mx11.au.com mx03.auone-net.jp
       ocn-fc-r-01.ocn.ad.jp bgmgate1.biglobe.ne.jp mgw1.mx.zaq.ne.jp].each do |host|
      assert_equal %w[jp_carrier_isp], keys("example.jp", [ host ])
    end
  end

  test "a subdomain of au.com is not the Japanese carrier: anyone can register one" do
    assert_empty keys("example.au.com", %w[mx1.example.au.com])
    assert_empty keys("example.au.com", %w[mail.au.com])
  end

  test "suffixes only match on a label boundary" do
    assert_empty keys("example.org", %w[notgmail-smtp-in.l.google.com])
    assert_empty keys("example.org", %w[gmail-smtp-in.l.google.com.evil.example])
    assert_empty keys("example.org", %w[inbound-smtp.us-east-1.amazonaws.com.evil.example])
    assert_empty keys("notagentmail.to")
    assert_empty keys("agentmail.to.evil.example")
  end

  test "an ordinary domain with its own mail server is nothing" do
    assert_empty keys("example.org", %w[mail.example.org])
    assert_empty keys("example.org", [])
    assert_empty keys(nil, nil)
  end

  test "severities reflect how much the mail setup says about the applicant" do
    severity = ->(key) { MailInfrastructure::PROVIDERS.find { it.key == key }.severity }

    assert_equal :critical, severity.("ai_bot")
    assert_equal :critical, severity.("test_mail")
    assert_equal :critical, severity.("inbound_email_api")
    assert_equal :warning, severity.("amazon_ses_inbound")
    %w[gmail google_workspace office365 cloudflare_email_routing domain_forwarding].each { assert_equal :info, severity.(it) }
  end
end
