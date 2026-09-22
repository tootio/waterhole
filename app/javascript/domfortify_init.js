import { init, status } from "domfortify"
import DOMPurify from "dompurify"

init({
  SANITIZER: DOMPurify,
  SANITIZER_CONFIG: {
    // Turbo renders its own <turbo-frame>, <turbo-stream> and
    // <turbo-cable-stream-source> elements. DOMPurify strips unknown custom
    // elements by default, which would silently break Frames, Streams and
    // the layout's live queue-badge subscription on every Turbo Drive visit.
    // Only the tag name is scoped to Turbo's "turbo-" namespace here: the
    // attribute name still has to be on this explicit list. A wildcard
    // attributeNameCheck would also let through attributes DOMPurify
    // otherwise always strips, like onclick, on any matching element.
    CUSTOM_ELEMENT_HANDLING: {
      tagNameCheck: /^turbo-/,
      attributeNameCheck: /^(?:id|class|target|targets|action|src|loading|busy|complete|disabled|autoscroll|refresh|channel|signed-stream-name|data-[\w-]+)$/,
      allowCustomizedBuiltInElements: false
    }
  }
})

if (!status().protected) {
  console.warn("DOMFortify is not protecting this page:", status().reason)
}
