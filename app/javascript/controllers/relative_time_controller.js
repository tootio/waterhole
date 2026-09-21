import { Controller } from "@hotwired/stimulus"

// Keeps "3 minutes ago" true. The server renders the phrase so it is correct
// before this connects and without JavaScript at all, but a moderation queue is
// left open for hours: a claim that says "2 minutes ago" all afternoon is worse
// than no timestamp, because deciding whether to take a request over is exactly
// a judgement about how long ago someone claimed it.
//
// Also the viewer's own wording and timezone, since moderation teams are spread
// across zones and "when?" should not need arithmetic.
const UNITS = [
  ["year",   31536000],
  ["month",   2592000],
  ["week",     604800],
  ["day",       86400],
  ["hour",       3600],
  ["minute",       60],
  ["second",        1]
]

// Re-render often enough that the text is never visibly stale, rarely enough
// that a queue of a hundred rows is not re-rendering constantly. The wording
// only changes as fast as its own unit does.
const INTERVALS = [
  [60,    5000],    // under a minute: seconds, so "now" does not linger
  [3600, 30000],    // under an hour: minutes
  [86400, 300000]   // under a day: hours
]
const SLOWEST = 3600000

export default class extends Controller {
  connect() {
    this.date = new Date(this.element.getAttribute("datetime"))
    if (isNaN(this.date)) return

    // The page language, not the browser one: this application is written in a
    // single language, and "vor 3 Tagen" inside an English sentence reads worse
    // than a timestamp nobody translated. The viewer TIMEZONE is theirs either
    // way, which is the part that would otherwise need arithmetic.
    this.locale = document.documentElement.lang || "en"

    this.formatter = new Intl.RelativeTimeFormat(this.locale, { numeric: "auto" })

    this.refresh = this.refresh.bind(this)
    this.refresh()
    // A Turbo morph refresh (see local_time_controller) resets this element's
    // text and title back to the server's own render -- a stale phrase and a
    // tooltip in the app's default timezone rather than the viewer's --
    // without disconnecting the controller. The text's own timer would
    // eventually overwrite that again, but for an old row that can be up to
    // an hour away (see SLOWEST), so refresh immediately instead of waiting.
    document.addEventListener("turbo:render", this.refresh)
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("turbo:render", this.refresh)
  }

  refresh() {
    this.setTitle()
    this.render()
  }

  setTitle() {
    // The exact moment, for the tooltip the server filled with its own.
    this.element.title = this.date.toLocaleString(this.locale, {
      year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit"
    })
  }

  render() {
    clearTimeout(this.timer)

    const seconds = (this.date.getTime() - Date.now()) / 1000
    const distance = Math.abs(seconds)
    const [unit, size] = UNITS.find(([, size]) => distance >= size) ?? UNITS.at(-1)

    // Negative is the past, which is what RelativeTimeFormat wants: -3 hours
    // reads as "3 hours ago", +3 as "in 3 hours".
    this.element.textContent = this.formatter.format(Math.round(seconds / size), unit)

    const interval = INTERVALS.find(([threshold]) => distance < threshold)
    this.timer = setTimeout(() => this.render(), interval ? interval[1] : SLOWEST)
  }
}
