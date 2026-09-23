import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Triage speed. Working a queue of eighty signups with a mouse is miserable, and
// this is the one thing server-rendered HTML genuinely cannot do.
//
//   j / k  move down / up      Enter  open        c  claim      x  select
export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.index = -1
    this.onKeydown = this.handle.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  handle(event) {
    // Never steal keys from someone typing a note or a filter. A checkbox is
    // not typing: after ticking a row with the mouse, j/k should still work.
    const active = document.activeElement
    const typing = (active?.tagName === "INPUT" && active.type !== "checkbox") ||
      active?.tagName === "TEXTAREA" || active?.isContentEditable
    if (typing) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    switch (event.key) {
      case "j": this.move(1); break
      case "k": this.move(-1); break
      case "c":
        if (!this.currentItem) return
        this.toggleClaim();
        break
      case "x":
        if (!this.currentItem) return
        this.toggleSelection()
        break
      default: return
    }
    event.preventDefault()
  }

  move(delta) {
    if (this.itemTargets.length === 0) return

    this.index = Math.max(0, Math.min(this.itemTargets.length - 1, this.index + delta))
    const item = this.itemTargets[this.index]
    item.focus()
  }

  // Clicks the row's bulk-select checkbox (a sibling of the link, see
  // _registration_request.html.erb), so bulk_select_controller.js sees an
  // ordinary tick. Resolved rows have none.
  toggleSelection() {
    this.currentItem.closest("li")?.querySelector("input[type=checkbox]")?.click()
  }

  get currentItem() {
    if (!document.activeElement) return
    return this.itemTargets.find(item => item === document.activeElement || item.contains(document.activeElement))
  }

  async toggleClaim() {
    const item = this.currentItem
    if (!item || this.toggling) return

    const url = item.dataset.claimUrl
    if (!url) return

    this.index = this.itemTargets.indexOf(item)
    const method = item.dataset.claimedByMe === "true" ? "DELETE" : "POST"

    this.toggling = true
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await Turbo.fetch(url, {
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
