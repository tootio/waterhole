import { Controller } from "@hotwired/stimulus"

// Collapses a long reason for joining, but only when it is actually long --
// most are short, and a Show more button on two lines is just noise.
export default class extends Controller {
  static targets = ["content", "toggle"]
  static values = { collapsedHeight: { type: Number, default: 240 } }

  connect() {
    if (this.contentTarget.scrollHeight <= this.collapsedHeightValue) return

    this.collapse()
    this.toggleTarget.classList.remove("hidden")
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
