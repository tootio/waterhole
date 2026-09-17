module Flags
  # The signup came from the address of a running Tor relay (Ip::TorRelays).
  #
  # `info`, one step below a datacenter: people use Tor for good reasons, and
  # the list includes non-exit relays, some run from home connections. The SaaS
  # Web spam shield draws the same line, rating Tor as merely sketchy and the
  # big clouds as highly sketchy.
  class TorRelay < Rule
    def call
      detect(:info, source: "Tor Project (Onionoo)") if request.ip_relay_tor?
    end
  end
end
