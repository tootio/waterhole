import { Controller } from "@hotwired/stimulus"

// Turbo always scrolls to the top after a visit, and for a form whose action
// redirects elsewhere, the anchor on that redirect's URL does not survive the
// trip through fetch's own redirect handling -- so there is no anchor left
// for Turbo to scroll to either. Landing back at the top of a long page reads
// as though the click did nothing, so this remembers where the moderator was
// and restores it once the resulting page finishes loading.
let rememberedScrollY = null

export default class extends Controller {
  remember() {
    rememberedScrollY = window.scrollY
  }

  // Turbo resets scroll to the top itself as part of rendering the visit, so
  // undoing that from `connect()` is too early -- it runs before Turbo's own
  // reset and gets overwritten. `turbo:load` is Turbo's last word on a visit,
  // dispatched once rendering and its own scrolling are done.
  restore() {
    if (rememberedScrollY === null) return

    window.scrollTo(0, rememberedScrollY)
    rememberedScrollY = null
  }
}
