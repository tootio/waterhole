require "json"

module Ip
  # Addresses of running Tor relays, from the Tor Project's Onionoo service.
  #
  # Every running relay's listening addresses (or_addresses), plus the exit
  # addresses Onionoo has seen where an exit's traffic leaves from somewhere
  # else. That is deliberately wider than exits alone -- the same list the
  # SaaS Web spam shield classifies as a sketchy network -- which also means a
  # non-exit relay run from someone's home connection is on it. Hence `info`.
  #
  # Relays come and go by the hour, so this refreshes hourly
  # (RefreshTorRelaysJob) rather than with the daily databases.
  module TorRelays
    NAME = "tor-relays"
    SOURCE_URL = "https://onionoo.torproject.org/details?type=relay&running=true&fields=or_addresses,exit_addresses"

    # The network has run thousands of relays for over a decade. Far fewer
    # means Onionoo answered with something other than the relay list.
    MINIMUM_RANGES = 1_000

    LIST = RangeList.new(NAME)

    module_function

    def include?(address) = LIST.include?(address)

    def installed? = LIST.installed?

    def path = LIST.path

    def reset! = LIST.reset!

    # "1.2.3.4:9001" and "[2001:db8::1]:9001" in or_addresses; bare
    # addresses in exit_addresses.
    def parse(download)
      JSON.parse(File.read(download)).fetch("relays").flat_map do |relay|
        or_addresses = Array(relay["or_addresses"]).map { it.sub(/:\d+\z/, "").delete_prefix("[").delete_suffix("]") }
        or_addresses + Array(relay["exit_addresses"])
      end
    end
  end
end
