import { Controller } from "@hotwired/stimulus"

// Inserts an email template placeholder such as {{username}} at the cursor of
// whichever field -- subject or body -- was focused last, so nobody has to
// remember the exact spelling.
export default class extends Controller {
  static targets = ["field"]

  remember(event) {
    this.lastField = event.currentTarget
  }

  insert(event) {
    const field = this.lastField || this.fieldTargets[this.fieldTargets.length - 1]
    if (!field) return

    field.focus()
    field.setRangeText(event.params.token, field.selectionStart, field.selectionEnd, "end")
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
