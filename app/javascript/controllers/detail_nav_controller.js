import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Keyboard shortcuts for a single registration request's page:
//   j / k  next / previous in the list (only when the request is in one)
//   c      claim / release
//   a / r  approve / reject and advance to the next in the list
//   n      jump to the note composer
export default class extends Controller {
  static targets = ["approveAndNextForm", "rejectAndNextForm", "noteInput", "claimBanner"]
  static values = {
    previousUrl: String,
    nextUrl: String,
    claimUrl: String
  }

  connect() {
    this.onKeydown = this.handle.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  handle(event) {
    // Never steal keys from someone typing a note or a filter.
    const tag = document.activeElement?.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || document.activeElement?.isContentEditable) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    switch (event.key) {
      case "k": if (this.hasPreviousUrlValue) Turbo.visit(this.previousUrlValue); break
      case "j": if (this.hasNextUrlValue) Turbo.visit(this.nextUrlValue); break
      case "c": this.toggleClaim(); break
      case "a": if (this.hasApproveAndNextFormTarget) this.approveAndNextFormTarget.requestSubmit(); break
      case "r": if (this.hasRejectAndNextFormTarget) this.rejectAndNextFormTarget.requestSubmit(); break
      case "n": if (this.hasNoteInputTarget) this.noteInputTarget.focus(); break
      default: return
    }
    event.preventDefault()
  }

  // Same mechanism as keyboard_nav_controller.js's toggleClaim, including
  // reading the current state off the DOM rather than a Stimulus value.
  async toggleClaim() {
    if (!this.hasClaimUrlValue || this.toggling) return
    const method = this.claimBannerTarget.dataset.claimedByMe === "true" ? "DELETE" : "POST"

    this.toggling = true
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await Turbo.fetch(this.claimUrlValue, {
        method,
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-Requested-With": "XMLHttpRequest",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        }
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } finally {
      this.toggling = false
    }
  }
}
