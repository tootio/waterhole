import { Controller } from "@hotwired/stimulus"

// Copies an email, IP or DNS record. Moderators paste these into other tools
// constantly, and selecting them by hand is error-prone.
export default class extends Controller {
  async copy(event) {
    const button = event.currentTarget
    const value = button.dataset.clipboardValue
    if (!value) return

    try {
      await navigator.clipboard.writeText(value)
      this.#flash(button, "copied")
    } catch {
      this.#flash(button, "press ⌘C")
    }
  }

  #flash(button, message) {
    const original = button.textContent
    button.textContent = message
    setTimeout(() => { button.textContent = original }, 1200)
  }
}
