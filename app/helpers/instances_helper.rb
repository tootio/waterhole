module InstancesHelper
  BADGE = "inline-flex rounded-full px-2 py-0.5 text-xs font-medium"

  STATUS_STYLES = {
    "verified"       => "bg-emerald-100 dark:bg-emerald-900 text-emerald-900 dark:text-emerald-200",
    "terms_outdated" => "bg-amber-100 dark:bg-amber-900 text-amber-900 dark:text-amber-200",
    "unverified"     => "bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-300 ring-1 ring-stone-200 dark:ring-stone-700",
    "revoked"        => "bg-stone-200 dark:bg-stone-700 text-stone-700 dark:text-stone-300"
  }.freeze

  def herd_status_badge(instance)
    tag.span instance.status.humanize,
      class: "#{BADGE} #{STATUS_STYLES.fetch(instance.status, "bg-stone-100 dark:bg-stone-800 text-stone-700 dark:text-stone-300")}"
  end

  # Participation, not the two keys behind it. Whether a herd's record opts in
  # is public, but whether the operator approved it is a decision about that
  # herd, and the only fact that concerns anyone else is the reciprocal one:
  # are they in, and therefore is your queue matched against theirs.
  def herd_signals_badge(instance)
    participating = instance.participating?

    tag.span participating ? "Signals on" : "Signals off",
      class: "#{BADGE} #{participating ? "bg-sky-100 dark:bg-sky-900 text-sky-900 dark:text-sky-200" : "bg-stone-100 dark:bg-stone-800 text-stone-500 dark:text-stone-400"}"
  end
end
