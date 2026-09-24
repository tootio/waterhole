import { Controller } from "@hotwired/stimulus"

// For a form whose turbo stream response replaces the form itself. Turbo puts
// focus back after a stream render only if the element focused beforehand has
// an id -- but it disables the submit button for the length of the request,
// which already dropped focus to <body> by then. So this remembers the id at
// submit time, and the replacement form's own controller puts focus back when
// it connects. Kept at module level, since the instance that remembers is
// gone by then.
let rememberedId = null

export default class extends Controller {
  connect() {
    if (!rememberedId) return

    const element = document.getElementById(rememberedId)
    if (!this.element.contains(element)) return

    rememberedId = null
    if (document.activeElement === document.body) element.focus()
  }

  remember() {
    rememberedId = document.activeElement?.id || null
  }
}
