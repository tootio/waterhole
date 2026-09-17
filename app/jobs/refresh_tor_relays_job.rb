# Tor relays come and go by the hour; the other address lists change daily.
class RefreshTorRelaysJob < RefreshIpDatabasesJob
  def perform = super(names: [ Ip::TorRelays::NAME ])
end
