module RegistrationRequests
  # Turns one Admin::Account payload into local attributes.
  #
  # Deliberately tolerant: Mastodon's nested account object is broad and varies
  # across versions, so anything not explicitly mapped is kept wholesale in
  # `raw` rather than guessed at.
  module Mapper
    module_function

    def call(payload)
      account = payload["account"] || {}

      {
        mastodon_account_id: payload["id"].to_s,
        username: payload["username"].presence || account["username"],
        display_name: account["display_name"].presence,
        bio: strip_html(account["note"]),
        avatar_url: account["avatar"].presence,
        account_url: account["url"].presence,
        locale: payload["locale"].presence,
        confirmed: !!payload["confirmed"],
        approved: !!payload["approved"],
        email: payload["email"].presence,
        ip: extract_ip(payload),
        invite_request: payload["invite_request"].presence,
        signed_up_at: parse_time(payload["created_at"]) || Time.current,
        raw: payload
      }
    end

    # `ip` is an object ({ip:, used_at:}) rather than a string, and may be null
    # even when `ips` has entries.
    def extract_ip(payload)
      direct = payload.dig("ip", "ip").presence
      return direct if direct

      Array(payload["ips"]).filter_map { it["ip"].presence }.first
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def strip_html(html)
      return nil if html.blank?

      ActionView::Base.full_sanitizer.sanitize(html).to_s.squish.presence
    end
  end
end
