import { Controller } from "@hotwired/stimulus"

// A toggle button and a popover panel next to it. A disclosure, not an ARIA
// menu -- the panel holds ordinary links and buttons reached with Tab, so there
// is no arrow-key contract to honour.
//
//   <div class="dropdown" data-controller="dropdown">
//     <button type="button" class="dropdown-toggle" popovertarget="x-menu"
//             aria-expanded="false" data-dropdown-target="toggle">…</button>
//     <div id="x-menu" popover class="dropdown-panel sm:w-56"
//          data-dropdown-target="panel">…</div>
//   </div>
//
// The popover puts the panel in the top layer, so it is never clipped and never
// grows the page, and closes it on a click outside and on Escape. Placement is
// CSS anchor positioning where the browser has it (application.css); here
// otherwise, with the same flip-when-it-does-not-fit rule. On a phone the
// stylesheet makes it a bottom sheet and this stays out of the way.
//
// What the popover does not do, this adds:
// - keeping aria-expanded current (render it "false"; a morph resets it)
// - a click on the sheet's backdrop closing it
// - closing when focus moves out of it
// - an Escape that closes it going no further (no dialog, no shortcut)
// - closing before Turbo caches the page, and before the browser puts it in
//   the back-forward cache on a full navigation, so Back never shows it open
//   (nor a phone's page still locked behind a sheet)
const ANCHORS = CSS.supports("position-area: bottom")
const SHEET = window.matchMedia("(width < 40rem)")
const GAP = 4 // between toggle and panel, as margin-top in the stylesheet
const EDGE = 8 // kept free at the viewport's edges

export default class extends Controller {
  static targets = ["toggle", "panel"]

  connect() {
    this.onToggle = this.sync.bind(this)
    this.onReposition = this.position.bind(this)
    this.onBeforeCache = this.close.bind(this)

    this.panelTarget.addEventListener("toggle", this.onToggle)
    this.element.addEventListener("keydown", this.keydown)
    this.element.addEventListener("focusout", this.focusout)
    this.panelTarget.addEventListener("click", this.backdropClick)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
    window.addEventListener("pagehide", this.onBeforeCache)
    this.sync()
  }

  disconnect() {
    this.panelTarget.removeEventListener("toggle", this.onToggle)
    this.element.removeEventListener("keydown", this.keydown)
    this.element.removeEventListener("focusout", this.focusout)
    this.panelTarget.removeEventListener("click", this.backdropClick)
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    window.removeEventListener("pagehide", this.onBeforeCache)
    this.stopFollowing()
  }

  get open() {
    return this.panelTarget.matches(":popover-open")
  }

  close() {
    if (this.open) this.panelTarget.hidePopover()
  }

  // Also runs on a morph that brings the panel back closed.
  sync() {
    const open = this.open
    this.toggleTarget.setAttribute("aria-expanded", String(open))
    if (ANCHORS) return

    // Only listened for while open, so a page full of closed dropdowns costs nothing.
    if (open) {
      this.position()
      window.addEventListener("scroll", this.onReposition, { capture: true, passive: true })
      window.addEventListener("resize", this.onReposition)
    } else {
      this.stopFollowing()
    }
  }

  stopFollowing() {
    window.removeEventListener("scroll", this.onReposition, { capture: true })
    window.removeEventListener("resize", this.onReposition)
  }

  // Under the toggle with right edges aligned; above it when it does not fit
  // below and there is more room above; never past the viewport, scrolling
  // inside when it is taller than the room it has.
  position() {
    const panel = this.panelTarget
    panel.style.top = panel.style.left = panel.style.maxHeight = ""
    if (SHEET.matches || !this.open) return

    const toggle = this.toggleTarget.getBoundingClientRect()
    const viewportWidth = document.documentElement.clientWidth
    const viewportHeight = document.documentElement.clientHeight
    const { offsetWidth: width, offsetHeight: height } = panel

    const below = viewportHeight - toggle.bottom - GAP - EDGE
    const above = toggle.top - GAP - EDGE
    const up = height > below && above > below
    const room = Math.max(up ? above : below, 0)
    const shown = Math.min(height, room)

    panel.style.top = `${up ? toggle.top - GAP - shown : toggle.bottom + GAP}px`
    panel.style.left = `${Math.max(EDGE, Math.min(toggle.right - width, viewportWidth - width - EDGE))}px`
    if (height > room) panel.style.maxHeight = `${room}px`
  }

  // The sheet's ::backdrop is part of the panel as far as events go, so the
  // popover's own light dismiss counts a click on it as inside.
  backdropClick = (event) => {
    if (event.target !== this.panelTarget) return

    const box = this.panelTarget.getBoundingClientRect()
    const inside = event.clientX >= box.left && event.clientX <= box.right &&
      event.clientY >= box.top && event.clientY <= box.bottom
    if (!inside) this.close()
  }

  keydown = (event) => {
    if (event.key !== "Escape" || !this.open) return

    // Ours alone: an Escape that closed this should not also close a dialog
    // around it or reach a shortcut handler.
    event.preventDefault()
    event.stopPropagation()
    this.close()
    this.toggleTarget.focus()
  }

  // Tabbing past the last item, or away with the mouse, leaves nothing open
  // behind. relatedTarget is null when focus leaves the window, which should
  // not count as leaving the dropdown.
  focusout = (event) => {
    if (event.relatedTarget && !this.element.contains(event.relatedTarget)) this.close()
  }
}
