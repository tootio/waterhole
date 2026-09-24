// Whether a single-key shortcut would land in text the moderator is typing --
// a note, a reply, a filter -- and so must be left alone. A checkbox is not
// typing: after ticking a row with the mouse, j/k should still work.
export function isTyping(element = document.activeElement) {
  if (!element) return false
  if (element.tagName === "INPUT") return element.type !== "checkbox"
  return element.tagName === "TEXTAREA" || element.isContentEditable
}
