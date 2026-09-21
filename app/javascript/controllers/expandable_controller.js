import { Controller } from "@hotwired/stimulus"

// Collapses a long reason for joining, but only when it is actually long --
// most are short, and a Show more button on two lines is just noise.
export default class extends Controller {
  static targets = ["content", "toggle"]
  static values = { collapsedHeight: { type: Number, default: 240 } }

  connect() {
    this.reconcile = this.reconcile.bind(this)
    this.reconcile()

    // A Turbo morph refresh (see local_time_controller) resets this element's
    // inline max-height and toggle label back to the server defaults without
    // disconnecting the controller, silently re-collapsing a moderator's
    // expanded reason. Reapply whatever they last chose after every render.
    document.addEventListener("turbo:render", this.reconcile)
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.reconcile)
  }

  reconcile() {
    if (this.contentTarget.scrollHeight <= this.collapsedHeightValue) return

    this.toggleTarget.classList.remove("hidden")
    this.expanded ? this.expand() : this.collapse()
  }

  toggle() {
    this.expanded ? this.collapse() : this.expand()
  }

  collapse() {
    this.expanded = false
    this.contentTarget.style.maxHeight = `${this.collapsedHeightValue}px`
    if (this.hasToggleTarget) this.toggleTarget.textContent = "Show more"
  }

  expand() {
    this.expanded = true
    this.contentTarget.style.maxHeight = "none"
    if (this.hasToggleTarget) this.toggleTarget.textContent = "Show less"
  }
}
