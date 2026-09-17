import { Controller } from "@hotwired/stimulus"

// Step 2 of the DNS instructions: whether the record carries signals=on.
// Both versions of the record are on the page; this shows the chosen one, so
// switching needs no round trip.
export default class extends Controller {
  static targets = [ "variant" ]

  choose(event) {
    const chosen = event.target.value
    this.variantTargets.forEach((variant) => { variant.hidden = variant.dataset.signals !== chosen })
  }
}
