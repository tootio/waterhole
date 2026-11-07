# Who receives mail for an address's domain, told from the domain itself, its MX
# hosts and their addresses (MailInfrastructure::Lookup). Each provider is one flag:
# see Flags::MailProviderRule. config/locales/en.yml holds what people read.
#
# A provider can be told by any of the three. Many services built for programs
# receive through Amazon SES or Cloudflare, so their MX says nothing about them and
# only their domains give them away. And a provider's MX is only evidence when every
# customer of it is that kind of customer: ilands.ai receives through Feishu, but
# Feishu is an ordinary workspace provider, so that domain is listed by name.
#
# After an edit here, `bin/rails waterhole:recompute_flags` reclassifies the pending
# queue from the hosts and addresses already stored, without asking DNS again. Decided
# requests keep their flags, so keep the label of a removed provider in en.yml.
module MailInfrastructure
  # mx       host suffixes, matched on a label boundary, or a Regexp for the host
  # domains  email domains, subdomains included
  # ips      addresses or CIDR ranges of MX hosts. Only what a service runs itself, as
  #          exact IPs: Contabo, Hetzner and DigitalOcean host unrelated customers in
  #          the same /24, so a hoster's range or ASN would flag innocent people
  # subsumes keys of providers that say nothing more once this one is known
  # unless_on_blocklist
  #          no flag when the disposable_email flag already says the same thing
  Provider = Data.define(:key, :severity, :mx, :domains, :ips, :subsumes, :unless_on_blocklist) do
    def initialize(key:, severity:, mx: [], domains: [], ips: [], subsumes: [], unless_on_blocklist: false)
      super(key:, severity:, mx:, domains:, ips: ips.map { IPAddr.new(it) }, subsumes:, unless_on_blocklist:)
    end

    def match_for(domain, hosts, addresses)
      if (listed = domains.find { within?(domain, it) })
        Match.new(provider: self, matched: listed, via: "domain")
      elsif (host = hosts.find { |candidate| mx.any? { host_matches?(candidate, it) } })
        Match.new(provider: self, matched: host, via: "mx")
      elsif (address = addresses.find { |candidate| ips.any? { it.include?(candidate) } })
        Match.new(provider: self, matched: address, via: "ip")
      end
    end

    private

    def host_matches?(host, pattern) = pattern.is_a?(Regexp) ? pattern.match?(host) : within?(host, pattern)

    def within?(name, suffix) = name == suffix || name.end_with?(".#{suffix}")
  end

  # via: "domain", "mx" or "ip", whichever gave the provider away.
  Match = Data.define(:provider, :matched, :via) do
    # The applicant can list any host as an MX next to their real one, so a match on
    # one only hides flags no more severe than its own. The address's domain is the
    # service's, and names what stands behind it whatever the severity.
    def hides?(other)
      provider.subsumes.include?(other.provider.key) &&
        (via == "domain" || rank(provider) >= rank(other.provider))
    end

    private

    def rank(provider) = Flag.severities.fetch(provider.severity.to_s)
  end

  # Naming the service says more than the mail platform behind it, and two flags
  # for one fact would rank the request above others in the riskiest-first sort.
  BEHIND_A_NAMED_SERVICE = %w[amazon_ses_inbound inbound_email_api].freeze

  PROVIDERS = [
    Provider.new(key: "ai_bot", severity: :critical, subsumes: BEHIND_A_NAMED_SERVICE,
      mx: %w[atomicmail.ai lumbox.co robotomail.com agentboxd.com],
      domains: %w[agentmail.to theagentmail.net atomicmail.ai lumbox.co trylumbox.com robotomail.co
                  homingbox.net ilands.ai ilands.app nylas.email revdokumail.com agent.qq.com]),
    # MailSlurp's many domains (mailslurp.*, slurp*.link, tempsmtp.com, …) all list
    # its own MX hosts behind SES, so they need no entries of their own.
    Provider.new(key: "test_mail", severity: :critical, subsumes: BEHIND_A_NAMED_SERVICE,
      mx: %w[mxslurp.click mailslurp.mx mailosaur.net testmail.app devinbox.io],
      domains: %w[zerodrop-sandbox.online]),
    # What the blocklist can't keep up with: TinyHost rotates through thousands of
    # domains that all share its MX. DropMail and TMaily give each domain its own
    # MX host, so new ones show only in the address. The named domains stay: they
    # match before any lookup, and still do if a service moves.
    #
    # The addresses, in order: TinyHost; Mail.tm; DropMail; TMaily. Services move and
    # addresses get reused, so these want reviewing now and then.
    Provider.new(key: "disposable_mail", severity: :warning, unless_on_blocklist: true,
      mx: %w[tinyhost.shop mail.tm],
      domains: %w[dropmail.me 10mail.org 10mail.info emltmp.com emlpro.com freeml.net spymail.one mimimail.me
                  maximail.fyi maximail.vip mailtowin.com pickmail.org pickmemail.com picomail.biz
                  hadjoy.com manglgih.com],
      ips: %w[144.91.107.45
              49.12.18.190 2a01:4f8:c011:4d4::1
              78.47.124.133 94.130.108.80 2a01:4f8:c0c:944::1 2a01:4f8:c0c:944::6
              159.195.145.63]),
    # A warning rather than critical: mostly programs, but also people forwarding
    # their own domain to a personal mailbox through a Lambda. MX can't tell which.
    Provider.new(key: "amazon_ses_inbound", severity: :warning,
      mx: [ /\Ainbound-smtp\.[a-z0-9-]+\.amazonaws\.com(\.cn)?\z/ ]),
    Provider.new(key: "inbound_email_api", severity: :critical,
      mx: %w[mx.sendgrid.net mailgun.org inbound.postmarkapp.com]),
    Provider.new(key: "cloudflare_email_routing", severity: :info, mx: %w[mx.cloudflare.net]),
    # Like Cloudflare: forwarding for one's own domain, by a service or by the
    # registrar. Namecheap and Porkbun also host mailboxes, so only their forwarding
    # hosts are matched. Forward Email hosts mailboxes on the same MX, which the help
    # text says.
    Provider.new(key: "domain_forwarding", severity: :info,
      mx: [ *%w[improvmx.com forwardemail.net],
            /\Aeforward\d+\.registrar-servers\.com\z/, /\Afwd\d+\.porkbun\.com\z/ ]),
    # Each service's own address domains are named, so they match before any lookup.
    # The MX hosts catch customers' own domains, and the alias domains of SimpleLogin
    # and Proton Pass, which are too many to list. Firefox Relay receives through
    # Amazon SES, so only its domains tell it. Blur's opayq.com is left to the
    # disposable blocklist, which already has it. iCloud's Hide My Email and
    # Fastmail's masked addresses look like ordinary mailboxes and can't be told.
    Provider.new(key: "email_alias", severity: :info, subsumes: BEHIND_A_NAMED_SERVICE,
      mx: %w[simplelogin.co alias.proton.me anonaddy.me addy.io addymail.com 33mail.com],
      domains: %w[aliasvault.net mozmail.com relay.firefox.com duck.com privaterelay.appleid.com
                  anonaddy.me anonaddy.com addy.io addymail.com 4wrd.cc mailer.me 33mail.com abinemail.com
                  burnermail.io erine.email spamgourmet.com spamgourmet.net spamgourmet.org]),
    Provider.new(key: "gmail", severity: :info, mx: %w[gmail-smtp-in.l.google.com]),
    Provider.new(key: "google_workspace", severity: :info,
      mx: %w[aspmx.l.google.com smtp.google.com googlemail.com]),
    Provider.new(key: "office365", severity: :info, mx: %w[mail.protection.outlook.com mx.microsoft]),
    Provider.new(key: "outlook_com", severity: :info, mx: %w[olc.protection.outlook.com]),
    Provider.new(key: "icloud_mail", severity: :info, mx: %w[mail.icloud.com]),
    Provider.new(key: "yahoo_mail", severity: :info, mx: %w[yahoodns.net mail.yahoo.co.jp]),
    Provider.new(key: "proton_mail", severity: :info, mx: %w[protonmail.ch]),
    Provider.new(key: "fastmail", severity: :info, mx: %w[messagingengine.com]),
    Provider.new(key: "zoho_mail", severity: :info,
      mx: %w[zoho.com zoho.eu zoho.in zoho.com.au zoho.jp zoho.sa zohocloud.ca zoho.com.cn zohomail.com]),
    Provider.new(key: "gmx_web_de", severity: :info, mx: %w[gmx.net web.de]),
    Provider.new(key: "yandex_mail", severity: :info, mx: %w[yandex.ru yandex.net]),
    Provider.new(key: "qq_mail", severity: :info, mx: %w[qq.com]),
    Provider.new(key: "feishu_lark", severity: :info, mx: %w[feishu.cn larksuite.com]),
    Provider.new(key: "tuta_mail", severity: :info, mx: %w[tutanota.de]),
    Provider.new(key: "posteo", severity: :info, mx: %w[posteo.de]),
    Provider.new(key: "mailfence", severity: :info, mx: %w[mailfence.com]),
    Provider.new(key: "mailo", severity: :info, mx: %w[mailo.com]),
    Provider.new(key: "seznam", severity: :info, mx: %w[seznam.cz]),
    Provider.new(key: "t_online", severity: :info, mx: %w[t-online.de]),
    Provider.new(key: "vivaldi_mail", severity: :info, mx: %w[vivaldi.net]),
    Provider.new(key: "onion_mail", severity: :info, mx: %w[onionmail.com]),
    # A pattern for au: anyone can register a subdomain of au.com.
    Provider.new(key: "jp_carrier_isp", severity: :info,
      mx: [ *%w[docomo.ne.jp softbank.ne.jp softbank.jp disney.ne.jp auone-net.jp ocn.ad.jp biglobe.ne.jp zaq.ne.jp
                xspmail.jp nifty.com commufa.jp wakwak.com odn.ne.jp plala.or.jp mose-mail.jp mail.gol.com stnet.ne.jp
                mics.ne.jp dream.jp dti.ne.jp],
            /\Amx\d+\.au\.com\z/ ])
  ].freeze

  module_function

  # One Match per provider found; hosts and addresses are nil for a domain never
  # looked up.
  def classify(domain:, hosts:, addresses: nil)
    matches  = PROVIDERS.filter_map { it.match_for(domain.to_s, Array(hosts), Array(addresses)) }
    matches.reject { |match| matches.any? { it.hides?(match) } }
  end
end
