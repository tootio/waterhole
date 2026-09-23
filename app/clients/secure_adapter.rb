require "resolv"
require "ipaddr"
require "socket"

module SecureAdapter
  module_function
  def adapter
    Faraday.default_adapter do |http|
      SsrfGuard.pin!(http)
    end
  end
end
