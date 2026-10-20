import { SHEET } from "lib/sheet"

// Stops the page scrolling behind a modal dialog, or behind a dropdown shown as
// a bottom sheet, the way GitHub does: hiding the page's overflow also takes
// its scrollbar away, so the scrollbar's width is measured while it is still
// there and given back as padding (application.css), and nothing behind the
// dialog shifts sideways.
//
// The lock follows the dialogs' and popovers' own state rather than being set
// and cleared by whoever opens them, so no close path can leave the page
// locked. It is re-checked on every change to the page, which also covers a
// Turbo visit replacing an open dialog's <body>.
const root = document.documentElement

function locked() {
  return !!(document.querySelector("dialog:modal") ||
    (SHEET.matches && document.querySelector(".dropdown-panel:popover-open")))
}

function sync() {
  const lock = locked()
  if (lock === root.hasAttribute("data-scroll-locked")) return

  if (lock) {
    // Measured before the attribute is set: once it is, the scrollbar is gone.
    root.style.setProperty("--scroll-gutter", `${window.innerWidth - root.clientWidth}px`)
    root.setAttribute("data-scroll-locked", "")
  } else {
    root.removeAttribute("data-scroll-locked")
    root.style.removeProperty("--scroll-gutter")
  }
}

// A mutation callback runs before the next paint, so a dialog opened with
// showModal() never shows a frame with the page unlocked. Popovers change no
// attribute when they open; their toggle event does not bubble, so it is
// caught on its way down instead.
new MutationObserver(sync).observe(root, { subtree: true, childList: true, attributes: true, attributeFilter: ["open"] })
document.addEventListener("toggle", sync, true)
SHEET.addEventListener("change", sync)
sync()
