import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // The dismiss button goes with the message it removes, which would leave a
  // keyboard user on <body>. Hand focus to the next message's dismiss button,
  // or to the main content once the last one is gone.
  close(event) {
    const message = event.currentTarget.closest("[role=status]")
    if (!message) return

    const hadFocus = message.contains(document.activeElement)
    message.remove()
    if (!hadFocus) return

    const next = this.element.querySelector("[data-action~='dismiss#close']")
    const target = next || document.getElementById("main-content")
    target?.focus({ preventScroll: true })
  }
}
