# The button/link styles repeated across the app, so a new one is composed
# from a shared recipe rather than copy-pasted -- which is how several ended
# up missing hover states or a focus ring in the first place.
module ButtonHelper
  # A ring with an offset gap matching the surrounding panel, rather than
  # flush against the element: a flush ring can disappear where it happens to
  # be close to the element's own fill color (this replaced a near-invisible
  # ring on the confirm dialog's Confirm button). Dark ring in light mode,
  # light ring in dark mode, so it's always the strongest possible contrast
  # against the gap regardless of what's under it.
  FOCUS_RING = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 " \
    "focus-visible:ring-offset-white dark:focus-visible:ring-offset-stone-900 " \
    "focus-visible:ring-stone-900 dark:focus-visible:ring-stone-100"

  # Each already bakes in FOCUS_RING, so a button built from one of these
  # can't end up missing it. Deliberately without a text/background color for
  # "outline", and without a hover treatment for "ghost": those are the two
  # places call sites actually disagree (an outline button's text is
  # sometimes muted, sometimes not; a ghost link's hover sometimes changes
  # text color, sometimes background, sometimes both) -- baking in one choice
  # there would fight whatever the caller passes as `extra`, since two
  # utilities for the same property on one element resolve unpredictably.
  VARIANTS = {
    solid: "rounded bg-stone-900 dark:bg-stone-100 text-white dark:text-stone-900 hover:bg-stone-800 dark:hover:bg-white #{FOCUS_RING}",
    outline: "rounded border border-stone-300 dark:border-stone-700 hover:bg-stone-100 dark:hover:bg-stone-800 #{FOCUS_RING}",
    outline_danger: "rounded border border-red-300 dark:border-red-800 bg-white dark:bg-stone-800 text-red-800 dark:text-red-300 hover:bg-red-50 dark:hover:bg-red-950 #{FOCUS_RING}",
    ghost: "text-stone-500 dark:text-stone-400 #{FOCUS_RING}"
  }.freeze

  # variant is one of VARIANTS' keys; extra is whatever's specific to this one
  # button -- padding, text size, width, its own hover color.
  def button_classes(variant, extra = nil)
    [ VARIANTS.fetch(variant), extra ].compact.join(" ")
  end

  # For a one-off button with its own color (Approve/Reject, Try now,
  # Release/Take over) that doesn't fit any of VARIANTS: still gets the ring.
  def focus_ring_classes = FOCUS_RING
end
