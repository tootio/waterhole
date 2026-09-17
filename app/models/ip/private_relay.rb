module Ip
  # Apple's iCloud Private Relay egress addresses.
  #
  # Safari users with Private Relay reach the web from Cloudflare, Akamai and
  # Fastly addresses, so an ordinary iPhone user signing up looks exactly like
  # a server in a datacenter. Apple publishes the egress ranges; checking them
  # tells the two apart. Refreshed daily with the MMDBs.
  #
  # Apple's list is ~290k CIDR lines (12 MB) with a city per range. Only
  # membership matters, and adjacent ranges merge down to a few thousand.
  module PrivateRelay
    NAME = "icloud-private-relay"
    SOURCE_URL = "https://mask-api.icloud.com/egress-ip-ranges.csv"

    # Apple's list has held hundreds of thousands of ranges. A download that
    # compiles to fewer is truncated or not the list at all, and replacing a
    # good file with it would quietly stop recognising relay users.
    MINIMUM_RANGES = 1_000

    LIST = RangeList.new(NAME)

    module_function

    def include?(address) = LIST.include?(address)

    def installed? = LIST.installed?

    def path = LIST.path

    def reset! = LIST.reset!

    # The CIDR in the first column of each line. Read as bytes: the city names
    # in the other columns are UTF-8 that need not be valid.
    def parse(download)
      File.foreach(download, encoding: "BINARY").filter_map do |line|
        cidr = line.split(",", 2).first.to_s.strip
        cidr unless cidr.empty?
      end
    end
  end
end
