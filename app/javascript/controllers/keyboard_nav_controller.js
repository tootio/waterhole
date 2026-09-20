import { Controller } from "@hotwired/stimulus"

// Triage speed. Working a queue of eighty signups with a mouse is miserable, and
// this is the one thing server-rendered HTML genuinely cannot do.
//
//   j / k  move down / up      Enter  open        c  claim
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
    // Never steal keys from someone typing a note or a filter.
    const tag = document.activeElement?.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || document.activeElement?.isContentEditable) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    switch (event.key) {
      case "j": this.move(1); break
      case "k": this.move(-1); break
      case "Enter": this.open(); break
      default: return
    }
    event.preventDefault()
  }

  move(delta) {
    if (this.itemTargets.length === 0) return

    this.index = Math.max(0, Math.min(this.itemTargets.length - 1, this.index + delta))
    const item = this.itemTargets[this.index]
    item.scrollIntoView({ block: "nearest" })
    this.itemTargets.forEach((el) => el.classList.remove("ring-2"))
    item.classList.add("ring-2")
  }

  open() {
    this.itemTargets[this.index]?.querySelector("a")?.click()
  }
}
