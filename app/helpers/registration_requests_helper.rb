module RegistrationRequestsHelper
  STATUS_STYLES = {
    "pending"            => "bg-amber-100 text-amber-900",
    "approved"           => "bg-emerald-100 text-emerald-900",
    "rejected"           => "bg-stone-200 text-stone-700",
    "approved_elsewhere" => "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200",
    "rejected_elsewhere" => "bg-stone-100 text-stone-600 ring-1 ring-stone-300",
    "expired"            => "bg-stone-100 text-stone-500 ring-1 ring-stone-200"
  }.freeze

  def status_badge(request)
    label = request.expired? ? "Expired" : request.status.humanize
    label += " (in Mastodon)" if request.resolved_elsewhere?
    tag.span label, class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{STATUS_STYLES.fetch(request.status, "bg-stone-100")}"
  end

  def severity_style(severity)
    case severity.to_s
    when "critical" then "bg-red-100 text-red-900 ring-1 ring-red-200"
    when "warning"  then "bg-amber-100 text-amber-900 ring-1 ring-amber-200"
    else "bg-sky-100 text-sky-900 ring-1 ring-sky-200"
    end
  end

  # Rendered from a datetime attribute so Stimulus can localise it client-side.
  def local_time(time, format: :long)
    return tag.span("—") if time.blank?

    tag.time time.to_fs(format), datetime: time.iso8601, title: time.to_fs(:long),
      data: { controller: "local-time" }
  end
end
