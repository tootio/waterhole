require "faraday"
require "faraday/retry"

module Mastodon
  # Thin, explicit wrapper over the Mastodon admin API.
  #
  # Constructed per-instance AND per-moderator: every write is made as a real
  # person, so Mastodon's own role permissions do the authorising and its audit
  # log names the human who decided.
  class Client
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15
    PAGE_LIMIT   = 200 # Mastodon's documented maximum

    attr_reader :base_url, :rate_limit_remaining, :rate_limit_reset_at

    def initialize(base_url:, access_token:, read_timeout: READ_TIMEOUT)
      @base_url     = base_url
      @access_token = access_token
      @read_timeout = read_timeout
    end

    def verify_credentials = get("/api/v1/accounts/verify_credentials")

    def instance_info = get("/api/v2/instance")

    # One page of local accounts awaiting approval.
    def pending_accounts(max_id: nil, limit: PAGE_LIMIT)
      response = raw_get("/api/v2/admin/accounts",
        origin: "local", status: "pending", limit:, max_id:)

      Page.from(response.body, response.headers["link"])
    end

    # Walks every page. Yields each account; stops at page_cap to bound a
    # runaway loop.
    def each_pending_account(page_cap: 25)
      return enum_for(:each_pending_account, page_cap:) unless block_given?

      max_id = nil
      pages  = 0

      loop do
        page = pending_accounts(max_id:)
        pages += 1
        page.records.each { |record| yield record, pages }

        max_id = page.next_max_id
        break if max_id.blank? || pages >= page_cap
      end

      pages
    end

    def admin_account(id) = get("/api/v1/admin/accounts/#{id}")

    def approve_account(id) = post("/api/v1/admin/accounts/#{id}/approve")

    def reject_account(id) = post("/api/v1/admin/accounts/#{id}/reject")

    private

    def get(path, **params) = raw_get(path, **params).body

    def raw_get(path, **params)
      request { connection.get(path, params.compact) }
    end

    def post(path, **params)
      request { connection.post(path, params.compact) }.body
    end

    def request
      response = yield
      record_rate_limit(response)
      raise_for_status(response)
      response
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError => e
      raise ConnectionError, "#{e.class}: #{e.message}"
    end

    def record_rate_limit(response)
      @rate_limit_remaining = response.headers["x-ratelimit-remaining"]&.to_i
      reset = response.headers["x-ratelimit-reset"]
      @rate_limit_reset_at = Time.zone.parse(reset) if reset.present?
    end

    def raise_for_status(response)
      case response.status
      when 200..299 then response
      when 401 then raise Unauthorized, error_message(response)
      when 403 then raise Forbidden, error_message(response)
      when 404 then raise NotFound, error_message(response)
      when 422 then raise Unprocessable, error_message(response)
      when 429 then raise RateLimited.new(error_message(response), reset_at: @rate_limit_reset_at)
      else raise ServerError, "HTTP #{response.status}: #{error_message(response)}"
      end
    end

    def error_message(response)
      body = response.body
      body.is_a?(Hash) ? body["error"].presence || body.to_s : body.to_s.truncate(200)
    end

    def connection
      @connection ||= Faraday.new(url: @base_url) do |f|
        f.request :json
        f.request :retry,
          max: 2,
          interval: 0.5,
          backoff_factor: 2,
          # 429 is handled by the caller via RateLimited#retry_after, which can
          # honour X-RateLimit-Reset; retrying it here would just burn budget.
          retry_statuses: [ 500, 502, 503, 504 ],
          methods: %i[get]
        f.response :json, content_type: /\bjson$/
        f.headers["Authorization"] = "Bearer #{@access_token}" if @access_token.present?
        f.headers["User-Agent"] = "Waterhole (+#{Waterhole::Deployment.base_url})"
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = @read_timeout
        f.adapter Faraday.default_adapter
      end
    end
  end
end
