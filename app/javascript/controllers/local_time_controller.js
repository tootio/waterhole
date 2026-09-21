import { Controller } from "@hotwired/stimulus"

// Renders server timestamps in the viewer's own timezone. Moderation teams are
// spread across zones, and "when did they sign up?" should not need arithmetic.
export default class extends Controller {
  connect() {
    this.render = this.render.bind(this)
    this.render()

    // A Turbo morph refresh (see turbo_refreshes_with in the layout, and
    // broadcast_refresh_later on RegistrationRequest) patches this element's
    // text back to the server-rendered, un-localized value in place, without
    // disconnecting the controller — so connect() alone won't catch it.
    document.addEventListener("turbo:render", this.render)
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.render)
  }

  render() {
    const iso = this.element.getAttribute("datetime")
    if (!iso) return

    const date = new Date(iso)
    if (isNaN(date)) return

    // The page language, not the browser one: see relative_time_controller.
    const locale = document.documentElement.lang || "en"

    this.element.textContent = date.toLocaleString(locale, {
      year: "numeric", month: "short", day: "numeric",
      hour: "2-digit", minute: "2-digit"
    })
  }
}
