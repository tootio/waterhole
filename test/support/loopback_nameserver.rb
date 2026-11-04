require "socket"

# A nameserver on loopback that gives every query the same reply, or by record type
# when the rcode is a Hash, for testing the real DnsAllowlist::Resolver: what it does
# with each kind of reply is what decides whether a resolver outage reads as a missing
# record.
class LoopbackNameserver
  def initialize(rcode, resources = [])
    @socket = UDPSocket.new
    @socket.bind("127.0.0.1", 0)
    @thread = Thread.new { serve(rcode, resources) }
  end

  def address = [ "127.0.0.1", @socket.addr[1] ]

  def stop
    @thread.kill
    @socket.close
  end

  module Helpers
    # Yields a real resolver that asks a nameserver replying like this.
    def answering(rcode, resources = [])
      nameserver = LoopbackNameserver.new(rcode, resources)
      yield resolver_asking(nameserver)
    ensure
      nameserver.stop
    end

    def resolver_asking(*nameservers)
      addresses = nameservers.map(&:address)
      Class.new(DnsAllowlist::Resolver) do
        define_method(:config) { super().merge(nameserver_port: addresses) }
      end.new
    end
  end

  private

  def serve(rcode, resources)
    loop do
      data, from = @socket.recvfrom(512)
      query = Resolv::DNS::Message.decode(data)
      reply = Resolv::DNS::Message.new(query.id)
      reply.qr = 1
      reply.rcode = rcode unless rcode.is_a?(Hash)
      query.each_question do |name, type|
        reply.rcode = rcode.fetch(type, Resolv::DNS::RCode::NoError) if rcode.is_a?(Hash)
        reply.add_question(name, type)
        resources.each { reply.add_answer(name, 60, it) }
      end
      @socket.send(reply.encode, 0, from[3], from[1])
    end
  end
end
