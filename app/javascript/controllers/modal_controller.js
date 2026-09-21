import { Controller } from "@hotwired/stimulus"

// Opens a same-origin link's page in a <dialog> instead of navigating to it.
// The href is fetched as XHR, which the server renders without its usual
// layout (see HelpController), and the result replaces the dialog's content
// before it is shown. One dialog is shared by every link on the page.
export default class extends Controller {
  static targets = ["dialog", "content", "title"]

  async open(event) {
    event.preventDefault()

    const { href } = event.currentTarget
    // aria-labelledby points at the title, so it needs real text as soon as
    // the dialog opens rather than staying empty until the fetch resolves --
    // the triggering link's own accessible name is the best guess until then.
    this.titleTarget.textContent = event.currentTarget.getAttribute("aria-label") || event.currentTarget.textContent.trim()
    this.contentTarget.innerHTML = '<p class="text-sm text-stone-500 dark:text-stone-400">Loading…</p>'
    if (!this.dialogTarget.open) {
      this.dialogTarget.showModal()
      // The dialog covers the viewport, but the page behind it can still be
      // scrolled with a wheel or touch unless we say otherwise ourselves.
      document.documentElement.classList.add("overflow-hidden")
    }

    try {
      const response = await fetch(href, { headers: { "X-Requested-With": "XMLHttpRequest", "Accept": "text/html" } })
      const template = document.createElement("template")
      template.innerHTML = await response.text()

      // The fetched page's own <h1> becomes the dialog's header title instead
      // of appearing twice.
      const heading = template.content.querySelector("h1")
      this.titleTarget.textContent = heading?.textContent ?? "Dialog"
      heading?.remove()

      this.contentTarget.replaceChildren(template.content)
    } catch {
      this.contentTarget.innerHTML = '<p class="text-sm text-red-700 dark:text-red-300">Couldn’t load this.</p>'
    }
  }

  close() {
    this.dialogTarget.close()
  }

  // A click landing on the <dialog> element itself, rather than something
  // inside it, is a click on the ::backdrop -- the dialog fills the viewport
  // while open, so nothing else could receive it there.
  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  // Fires on Esc too, since that also triggers the dialog's native close.
  // Clears the content rather than leaving applicant details sitting in a
  // hidden dialog until the next one is opened, and restores page scrolling.
  clear() {
    document.documentElement.classList.remove("overflow-hidden")
    this.titleTarget.textContent = ""
    this.contentTarget.innerHTML = ""
  }
}
