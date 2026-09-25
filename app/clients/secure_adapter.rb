# Sets a Faraday connection's adapter to Net::HTTP with SsrfGuard pinning
# every connection it opens. Call it in place of `f.adapter`:
#
#   Faraday.new { |f| SecureAdapter.use(f) }
#
module SecureAdapter
  module_function

  def use(faraday)
    faraday.adapter(:net_http) { |http| SsrfGuard.pin!(http) }
  end
end
