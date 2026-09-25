import { Controller } from "@hotwired/stimulus"

// A <details> dropdown: the <summary> is the toggle, the rest of it the
// content. A disclosure, not an ARIA menu -- the panel holds ordinary links and
// buttons reached with Tab, so there is no arrow-key contract to honour.
//
// Render the <summary> with aria-controls (the panel's id) and
// aria-expanded="false" rather than leaving them to connect(): a Turbo morph
// resets attributes to what the server sent, and does not reconnect this.
//
// <details> already opens and closes itself; this adds what it lacks:
// - keeping aria-expanded current, which not every browser and screen reader
//   pair reports for <details> on its own
// - closing on a click outside, on Escape (focus back on the toggle), and when
//   focus moves out of it
// - closing before Turbo caches the page, so Back never shows it open
export default class extends Controller {
  connect() {
    this.summary = this.element.querySelector(":scope > summary")

    this.onToggle = this.sync.bind(this)
    this.onClickOutside = this.clickOutside.bind(this)
    this.onKeydown = this.keydown.bind(this)
    this.onFocusout = this.focusout.bind(this)
    this.onBeforeCache = this.close.bind(this)

    this.element.addEventListener("toggle", this.onToggle)
    this.element.addEventListener("keydown", this.onKeydown)
    this.element.addEventListener("focusout", this.onFocusout)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
    this.sync()
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.onToggle)
    this.element.removeEventListener("keydown", this.onKeydown)
    this.element.removeEventListener("focusout", this.onFocusout)
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    document.removeEventListener("click", this.onClickOutside)
  }

  close() {
    this.element.open = false
  }

  // Also runs on a morph that brings the element back closed.
  sync() {
    const open = this.element.open
    this.summary.setAttribute("aria-expanded", String(open))
    // Only listened for while open, so a page full of closed dropdowns costs nothing.
    if (open) document.addEventListener("click", this.onClickOutside)
    else document.removeEventListener("click", this.onClickOutside)
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  keydown(event) {
    if (event.key !== "Escape" || !this.element.open) return

    // Ours alone: an Escape that closed this should not also close a dialog
    // around it or reach a shortcut handler.
    event.preventDefault()
    event.stopPropagation()
    this.close()
    this.summary.focus()
  }

  // Tabbing past the last item, or away with the mouse, leaves nothing open
  // behind. relatedTarget is null when focus leaves the window, which should
  // not count as leaving the dropdown.
  focusout(event) {
    if (event.relatedTarget && !this.element.contains(event.relatedTarget)) this.close()
  }
}
