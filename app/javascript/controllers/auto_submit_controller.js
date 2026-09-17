import { Controller } from "@hotwired/stimulus"

// Submits the filter form as you type, debounced, so the queue narrows without
// a Filter button. The form targets a Turbo Frame, so only the list is replaced.
export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
