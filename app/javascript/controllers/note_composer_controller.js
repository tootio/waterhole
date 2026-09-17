import { Controller } from "@hotwired/stimulus"

// The composer is marked data-turbo-permanent so that a half-typed note survives
// the refresh-morphs that claims and decisions broadcast. That protection also
// means Turbo will not replace it, so a server-rendered "reset the form" stream
// would be silently ignored -- the composer has to clear itself here instead.
export default class extends Controller {
  static targets = ["input", "counter"]

  connect() { this.count() }

  count() {
    const length = this.inputTarget.value.length
    this.counterTarget.textContent = length === 0 ? "" : `${length} characters`
  }

  reset(event) {
    // Only clear when the note actually saved; a validation failure should leave
    // the text where the moderator can fix it.
    if (event.detail?.success === false) return

    this.inputTarget.value = ""
    this.count()
  }
}
