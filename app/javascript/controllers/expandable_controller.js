import { Controller } from "@hotwired/stimulus"

// Collapses a long reason for joining, but only when it is actually long.
export default class extends Controller {
  static targets = ["content", "toggle"]
  static values = { collapsedHeight: { type: Number, default: 240 } }

  connect() {
    this.expanded = false
    this.reconcile()
  }

  reconcile() {
    if (this.contentTarget.scrollHeight <= this.collapsedHeightValue) return

    this.toggleTarget.classList.remove("hidden")
    this.apply()
  }

  toggle() {
    this.expanded = !this.expanded
    this.apply()
  }

  apply() {
    this.contentTarget.style.maxHeight = this.expanded ? "none" : `${this.collapsedHeightValue}px`
    this.toggleTarget.textContent = this.expanded ? "Show less" : "Show more"
  }
}
