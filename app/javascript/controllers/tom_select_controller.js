import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

// Progressive enhancement for a <select multiple>: the choices show as chips
// with a remove button, and typing filters the options. Without JavaScript the
// plain multiple select still submits the same parameters.
//
// Put the controller on an element wrapping the select, not on the select:
// TomSelect hides the select and inserts its own markup next to it, and the
// wrapper is what this keeps out of the way of Turbo.
//
// The styling is ours (.ts-* in application.css), not tom-select's stylesheet,
// so it looks like the app's other form controls in light and dark.
export default class extends Controller {
  static targets = ["select"]
  static values = { placeholder: String }

  connect() {
    this.clearRestoredMarkup()
    this.tomSelect = new TomSelect(this.selectTarget, {
      plugins: { remove_button: { title: "Remove" } },
      placeholder: this.placeholderValue,
      hidePlaceholder: true,
      hideSelected: true,
      closeAfterSelect: true,
      maxOptions: null,
      // The select's own classes size the wrapper like the other controls; the
      // dropdown is styled separately.
      copyClassesToDropdown: false
    })

    // A refresh morph (every claim and decision broadcasts one) would strip the
    // markup TomSelect added, since the server never rendered it. Skipping the
    // wrapper keeps the chips and whatever is being typed.
    this.onBeforeMorph = (event) => {
      if (event.target === this.element) event.preventDefault()
    }
    // The snapshot Turbo caches for Back copies the options' `selected`
    // attributes -- still the server's, whatever was chosen since.
    this.onBeforeCache = () => {
      for (const option of this.selectTarget.options) option.toggleAttribute("selected", option.selected)
    }

    this.element.addEventListener("turbo:before-morph-element", this.onBeforeMorph)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-morph-element", this.onBeforeMorph)
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    this.tomSelect?.destroy()
    this.tomSelect = null
  }

  // A page Turbo restores from its cache (Back) carries the markup of the
  // instance that was live when it was cached, but not the instance. Not
  // undone on turbo:before-cache instead: the queue's filter form stays on
  // screen while its frame advances the URL, and that caches the page too.
  clearRestoredMarkup() {
    this.element.querySelectorAll(".ts-wrapper").forEach((wrapper) => wrapper.remove())
    this.selectTarget.classList.remove("tomselected", "ts-hidden-accessible")
    this.selectTarget.removeAttribute("tabindex")
  }
}
