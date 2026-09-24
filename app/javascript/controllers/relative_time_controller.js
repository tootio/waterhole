import { Controller } from "@hotwired/stimulus"
import { formatLocal, pageLocale } from "controllers/local_time_controller"

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
  ["minute",       60]
]

// Under a minute either way reads as "now", in the formatter's own words for
// the page language, rather than a seconds count that changes every few
// seconds. RelativeTimeFormat has no "less than a minute" in any language.
const NOW = 60

// Re-render often enough that the text is never visibly stale, rarely enough
// that a queue of a hundred rows is not re-rendering constantly. The wording
// only changes as fast as its own unit does.
const INTERVALS = [
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
    this.formatter = new Intl.RelativeTimeFormat(pageLocale(), { numeric: "auto" })

    this.refresh()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  // Also bound to turbo:render (see relative_time in RegistrationRequestsHelper):
  // a Turbo morph refresh (see local_time_controller) resets this element's
  // text and title back to the server's own render -- a stale phrase and a
  // tooltip in the app's default timezone rather than the viewer's -- without
  // disconnecting the controller. The text's own timer would eventually
  // overwrite that again, but for an old row that can be up to an hour away
  // (see SLOWEST), so refresh immediately instead of waiting.
  refresh() {
    if (isNaN(this.date)) return

    // The exact moment, for the tooltip the server filled with its own.
    this.element.title = formatLocal(this.date)
    this.render()
  }

  render() {
    clearTimeout(this.timer)

    const seconds = (this.date.getTime() - Date.now()) / 1000
    const distance = Math.abs(seconds)

    if (distance < NOW) {
      // numeric "auto" turns zero into a word: "now", "jetzt", "maintenant".
      this.element.textContent = this.formatter.format(0, "second")
      // Nothing changes until it is a minute in the past, even for a moment
      // that is still ahead: that is seconds + NOW from now.
      this.timer = setTimeout(() => this.render(), (seconds + NOW) * 1000)
      return
    }

    const [unit, size] = UNITS.find(([, size]) => distance >= size)

    // Negative is the past, which is what RelativeTimeFormat wants: -3 hours
    // reads as "3 hours ago", +3 as "in 3 hours".
    this.element.textContent = this.formatter.format(Math.round(seconds / size), unit)

    const interval = INTERVALS.find(([threshold]) => distance < threshold)
    this.timer = setTimeout(() => this.render(), interval ? interval[1] : SLOWEST)
  }
}
