import { Controller } from "@hotwired/stimulus"

// Turbo always scrolls to the top after a visit, and for a form whose action
// redirects elsewhere, the anchor on that redirect's URL does not survive the
// trip through fetch's own redirect handling -- so there is no anchor left
// for Turbo to scroll to either. Landing back at the top of a long page reads
// as though the click did nothing, so this remembers where the moderator was
// and restores it once the resulting page finishes loading.
//
// Focus gets the same treatment: the visit replaces the whole body, so a
// keyboard user would otherwise be left on <body> of a page that looks as if
// nothing moved. Only an element with an id can be found again on the new page.
let rememberedScrollY = null
let rememberedFocusId = null

export default class extends Controller {
  remember() {
    rememberedScrollY = window.scrollY
    rememberedFocusId = document.activeElement?.id || null
  }

  // Turbo resets scroll to the top itself as part of rendering the visit, so
  // undoing that from `connect()` is too early -- it runs before Turbo's own
  // reset and gets overwritten. `turbo:load` is Turbo's last word on a visit,
  // dispatched once rendering and its own scrolling are done.
  restore() {
    if (rememberedScrollY === null) return

    if (rememberedFocusId) document.getElementById(rememberedFocusId)?.focus({ preventScroll: true })
    window.scrollTo(0, rememberedScrollY)
    rememberedScrollY = null
    rememberedFocusId = null
  }
}
