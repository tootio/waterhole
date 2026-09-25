import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { isTyping } from "lib/typing"

// Triage speed. Working a queue of eighty signups with a mouse is miserable, and
// this is the one thing server-rendered HTML genuinely cannot do.
//
//   j / k  move down / up      Enter  open        c  claim      x  select
//
// j on the last row loads more (load_more_controller.js) and moves into them.
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
    if (isTyping()) return
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
    const items = this.itemTargets
    if (items.length === 0) return

    if (delta > 0 && this.index >= items.length - 1 && this.loadMore?.available) {
      this.advanceAfterLoad()
      return
    }

    this.index = Math.max(0, Math.min(items.length - 1, this.index + delta))
    items[this.index].focus()
  }

  // A "j" pressed again while loading waits on the same load, not a second one.
  async advanceAfterLoad() {
    const { index } = this
    const count = this.itemTargets.length
    if (!await this.loadMore.load()) return
    // Moved on meanwhile (a "k", or a click)? Then leave focus alone. Nothing
    // new? Then stop here rather than ask again.
    if (this.index !== index || this.itemTargets.length <= count) return

    this.move(1)
  }

  get loadMore() {
    const element = this.element.closest("[data-controller~=load-more]")
    return element && this.application.getControllerForElementAndIdentifier(element, "load-more")
  }

  // Clicks the row's bulk-select checkbox (a sibling of the link, see
  // _registration_request.html.erb), so bulk_select_controller.js sees an
  // ordinary tick. Resolved rows have none.
  toggleSelection() {
    this.currentItem.closest("li")?.querySelector("input[type=checkbox]")?.click()
  }

  get currentItem() {
    return this.itemTargets.find(item => item === document.activeElement || item.contains(document.activeElement))
  }

  async toggleClaim() {
    const item = this.currentItem
    if (this.toggling) return

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
