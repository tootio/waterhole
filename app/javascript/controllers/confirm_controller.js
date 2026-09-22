import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Replaces the browser's window.confirm for every [data-turbo-confirm] link
// or button with this <dialog>. Turbo awaits Turbo.config.forms.confirm and
// only proceeds with the submission if it resolves truthy -- see
// FormSubmission#start in turbo-rails, which is also what makes this apply to
// data-turbo-method links: they're converted into a form carrying the same
// data-turbo-confirm attribute before being submitted.
export default class extends Controller {
  static targets = ["dialog", "message"]

  connect() {
    Turbo.config.forms.confirm = this.confirm.bind(this)
  }

  confirm(message) {
    this.messageTarget.textContent = message
    // Cleared up front: <form method="dialog"> only sets returnValue when a
    // submit button closes it, so a stale value from a previous confirmation
    // would otherwise survive an Escape press or a backdrop click here.
    this.dialogTarget.returnValue = ""
    document.documentElement.classList.add("overflow-hidden")
    this.dialogTarget.showModal()

    return new Promise((resolve) => {
      this.dialogTarget.addEventListener("close", () => {
        document.documentElement.classList.remove("overflow-hidden")
        resolve(this.dialogTarget.returnValue === "confirm")
      }, { once: true })
    })
  }

  // A click landing on the <dialog> element itself, rather than something
  // inside it, is a click on the ::backdrop -- the dialog fills the viewport
  // while open, so nothing else could receive it there. Closing without a
  // returnValue resolves the promise above to false, i.e. cancelled.
  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }
}
