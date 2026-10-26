module StatsHelper
  # The queue filter's words for the same statuses, so the chart legend and the
  # filter a moderator would use to look closer agree.
  OUTCOME_LABELS = {
    "pending"            => "Pending",
    "approved"           => "Approved",
    "approved_elsewhere" => "Approved in Mastodon",
    "rejected"           => "Rejected",
    "rejected_elsewhere" => "Rejected in Mastodon",
    "expired"            => "Expired"
  }.freeze

  def stats_percent(part, whole)
    return "—" if whole.zero?

    number_to_percentage(100.0 * part / whole, precision: 0)
  end

  # Days are UTC days (see RegistrationStats::Series::PERIODS), so they are
  # labelled as dates, not converted; hours go through local-time like every
  # other timestamp here.
  def stats_bucket_label(series, bucket)
    series.hourly? ? local_time(bucket, format: :short) : tag.time(bucket.to_date.to_fs(:long), datetime: bucket.to_date.iso8601)
  end

  # The chart's data, for the chart controller: JSON in a data attribute, as no
  # inline script gets past the content security policy.
  def stats_chart(series, kind:, label:)
    data = { controller: "chart", action: "turbo:morph-element->chart#morphed",
             chart_series_value: series.to_chart.to_json, chart_kind_value: kind }
    data[:chart_labels_value] = OUTCOME_LABELS.to_json if kind == "outcomes"

    tag.div class: "chart min-h-72 w-full", role: "img", aria: { label: }, data:
  end
end
