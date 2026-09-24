import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { isTyping } from "lib/typing"

// Keyboard shortcuts for a single registration request's page:
//   j / k  next / previous in the list (only when the request is in one)
//   c      claim / release
//   a / r  approve / reject and advance to the next in the list
//   n      jump to the note composer
export default class extends Controller {
  static targets = ["approveAndNextForm", "rejectAndNextForm", "noteInput", "claimBanner"]
  static values = {
    previousUrl: String,
    nextUrl: String
  }

  connect() {
    this.onKeydown = this.handle.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  handle(event) {
    if (isTyping()) return
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

  toggleClaim() {
    this.claimBannerTarget.querySelector("button")?.click()
  }
}
