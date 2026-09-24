import { Controller } from "@hotwired/stimulus"

// Serves two purposes:
// (1) Fix a Turbo Drive glitch: When Turbo tries to handle this link, it gets a new page visit.
// Losing the focus in the process (when Turbo already had it in its cache).
// (2) Does not add the `#main-content` hash to the URL/the browser history stack.
export default class extends Controller {
  skip(event) {
    const target = document.getElementById(this.element.hash.slice(1))
    if (!target) return

    event.preventDefault()
    target.focus()
    target.scrollIntoView()
  }
}
