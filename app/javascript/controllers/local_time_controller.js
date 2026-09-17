import { Controller } from "@hotwired/stimulus"

// Renders server timestamps in the viewer's own timezone. Moderation teams are
// spread across zones, and "when did they sign up?" should not need arithmetic.
export default class extends Controller {
  connect() {
    const iso = this.element.getAttribute("datetime")
    if (!iso) return

    const date = new Date(iso)
    if (isNaN(date)) return

    this.element.textContent = date.toLocaleString([], {
      year: "numeric", month: "short", day: "numeric",
      hour: "2-digit", minute: "2-digit"
    })
  }
}
