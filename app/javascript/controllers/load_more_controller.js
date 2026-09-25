import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// "Load more" on the queue: appends the next rows by turbo stream rather than
// replacing the frame, so the bulk selection and the focused row survive.
//
// The live queue morphs itself on every claim, decision and sync, and that
// refresh re-requests the current URL. So after each load the URL is moved to
// the link's ?page=N, which renders everything through page N: the refresh,
// a reload and the back button all show the rows that were loaded.
export default class extends Controller {
  static targets = ["link"]

  // Resolves to whether rows were added, once they are in the DOM.
  load(event) {
    event?.preventDefault()
    if (this.loading) return this.loading

    const link = event?.currentTarget ?? (this.hasLinkTarget ? this.linkTarget : null)
    if (!link) return Promise.resolve(false)

    this.loading = this.fetch(link).finally(() => { this.loading = null })
    return this.loading
  }

  get available() {
    return this.hasLinkTarget
  }

  async fetch(link) {
    const url = new URL(link.href)
    const streamUrl = new URL(url)
    streamUrl.searchParams.set("from", link.dataset.from)

    let response
    try {
      response = await Turbo.fetch(streamUrl, {
        headers: { "Accept": "text/vnd.turbo-stream.html", "X-Requested-With": "XMLHttpRequest" }
      })
    } catch {
      return false
    }
    if (!response.ok) return false

    Turbo.renderStreamMessage(await response.text())
    // Turbo performs the stream on the next frame, and in that same frame puts
    // focus back where it was before rendering. Resolve only after both, so a
    // caller moving focus into the new rows is not undone.
    await nextFrame()
    await nextFrame()
    // history.state keeps Turbo's restoration identifier.
    history.replaceState(history.state, "", url)
    return true
  }
}

const nextFrame = () => new Promise(resolve => requestAnimationFrame(resolve))
