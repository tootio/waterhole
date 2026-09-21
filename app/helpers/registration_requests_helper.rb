module RegistrationRequestsHelper
  # The only filters a queue link may carry. Handing url_for the raw query
  # string would let ?host= or ?protocol= rewrite a link into another origin
  # or a javascript: URL, so links are always rebuilt from this allowlist
  # instead of from whatever the request happens to have on it.
  FILTER_PARAMS = %i[status claim email flag search sort].freeze

  STATUS_STYLES = {
    "pending"            => "bg-amber-100 dark:bg-amber-900 text-amber-900 dark:text-amber-200",
    "approved"           => "bg-emerald-100 dark:bg-emerald-900 text-emerald-900 dark:text-emerald-200",
    "rejected"           => "bg-stone-200 dark:bg-stone-700 text-stone-700 dark:text-stone-300",
    "approved_elsewhere" => "bg-emerald-50 dark:bg-emerald-950 text-emerald-700 dark:text-emerald-300 ring-1 ring-emerald-200 dark:ring-emerald-900",
    "rejected_elsewhere" => "bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-300 ring-1 ring-stone-300 dark:ring-stone-700",
    "expired"            => "bg-stone-100 dark:bg-stone-800 text-stone-500 dark:text-stone-400 ring-1 ring-stone-200 dark:ring-stone-700"
  }.freeze

  # Carries the queue's current filters onto a row's link, so "back to queue"
  # from the detail page can restore them. A plain helper rather than a
  # controller method, since this partial is also rendered from
  # ClaimsController's turbo_stream responses.
  def queue_row_path(registration_request)
    registration_request_path(registration_request, params.permit(*FILTER_PARAMS))
  end

  def status_badge(request)
    label = request.expired? ? "Expired" : request.status.humanize
    label += " (in Mastodon)" if request.resolved_elsewhere?
    tag.span label, class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{STATUS_STYLES.fetch(request.status, "bg-stone-100 dark:bg-stone-800")}"
  end

  def severity_style(severity)
    case severity.to_s
    when "critical" then "bg-red-100 dark:bg-red-900 text-red-900 dark:text-red-200 ring-1 ring-red-200 dark:ring-red-900"
    when "warning"  then "bg-amber-100 dark:bg-amber-900 text-amber-900 dark:text-amber-200 ring-1 ring-amber-200 dark:ring-amber-900"
    else "bg-sky-100 dark:bg-sky-900 text-sky-900 dark:text-sky-200 ring-1 ring-sky-200 dark:ring-sky-900"
    end
  end

  # "3 minutes ago", or "in 6 days" for a deadline. Rendered server-side so it
  # is right without JavaScript, and re-rendered by the relative-time controller
  # so it stays right on a page left open, which a queue is.
  def relative_time(time)
    return tag.span("—") if time.blank?

    distance = time_ago_in_words(time)
    phrase   = time.future? ? "in #{distance}" : "#{distance} ago"

    tag.time phrase, datetime: time.iso8601, title: time.to_fs(:long),
      data: { controller: "relative-time" }
  end

  # Rendered from a datetime attribute so Stimulus can localise it client-side.
  def local_time(time, format: :long)
    return tag.span("—") if time.blank?

    tag.time time.to_fs(format), datetime: time.iso8601, title: time.to_fs(:long),
      data: { controller: "local-time" }
  end
end
