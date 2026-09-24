import { Controller } from "@hotwired/stimulus"

// The page language, not the browser one: see relative_time_controller.
export const pageLocale = () => document.documentElement.lang || "en"

let formatter = null

// Shared with relative_time_controller's tooltip, so the two always read the
// same, and built once: a queue page formats a timestamp on every row, again
// on every morph refresh.
export function formatLocal(date) {
  formatter ??= new Intl.DateTimeFormat(pageLocale(), {
    year: "numeric", month: "short", day: "numeric",
    hour: "2-digit", minute: "2-digit"
  })
  return formatter.format(date)
}

// Renders server timestamps in the viewer's own timezone. Moderation teams are
// spread across zones, and "when did they sign up?" should not need arithmetic.
export default class extends Controller {
  connect() {
    this.render()
  }

  render() {
    const date = new Date(this.element.getAttribute("datetime"))
    if (isNaN(date)) return

    this.element.textContent = formatLocal(date)
  }
}
