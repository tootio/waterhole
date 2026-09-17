require "ipaddr"

module Ip
  # A downloaded list of addresses, compiled into merged integer ranges so a
  # lookup is a binary search. Shared by Ip::PrivateRelay and Ip::TorRelays;
  # RefreshIpDatabasesJob downloads, compiles and installs them.
  #
  # The compiled file is a line per range, "family first last" in decimal:
  # trivial to read back, and a fraction of the source's size once adjacent
  # ranges merge.
  class RangeList
    attr_reader :name

    def initialize(name)
      @name = name
      @mutex = Mutex.new
    end

    def path = Databases.directory.join("#{name}.ranges")

    def installed? = path.exist?

    def include?(address)
      ip = IPAddr.new(address.to_s)
      ip = ip.native if ip.ipv4_mapped?
      list = ranges[ip.ipv4? ? 4 : 6]
      return false if list.blank?

      value = ip.to_i
      # The last range starting at or before the address, if any.
      index = list.bsearch_index { |(first, _)| first > value } || list.size
      index.positive? && list[index - 1][1] >= value
    rescue IPAddr::InvalidAddressError
      false
    end

    # Reloaded when the file changes, so a refresh reaches a running worker
    # without a restart.
    def ranges
      mtime = path.exist? ? path.mtime : nil
      @mutex.synchronize do
        if @ranges.nil? || @loaded_mtime != mtime
          @ranges = mtime ? read : {}
          @loaded_mtime = mtime
        end
        @ranges
      end
    end

    def reset! = @mutex.synchronize { @loaded_mtime = @ranges = nil }

    # { 4 => [[first, last], ...], 6 => [...] }, sorted and merged, from
    # addresses or CIDR blocks.
    def self.compile(cidrs)
      ranges = { 4 => [], 6 => [] }
      cidrs.each do |cidr|
        range = IPAddr.new(cidr).to_range
        ranges[range.first.ipv4? ? 4 : 6] << [ range.first.to_i, range.last.to_i ]
      end
      ranges.transform_values { merge(it) }
    end

    def self.merge(list)
      list.sort.each_with_object([]) do |(first, last), merged|
        if merged.any? && first <= merged.last[1] + 1
          merged.last[1] = [ merged.last[1], last ].max
        else
          merged << [ first, last ]
        end
      end
    end

    def self.write(ranges, to:)
      File.open(to, "w") do |file|
        ranges.each { |family, list| list.each { |(first, last)| file.puts("#{family} #{first} #{last}") } }
      end
    end

    def self.range_count(ranges) = ranges.values.sum(&:size)

    private

    def read
      path.each_line.with_object({ 4 => [], 6 => [] }) do |line, ranges|
        family, first, last = line.split
        ranges[family.to_i] << [ first.to_i, last.to_i ]
      end
    end
  end
end
