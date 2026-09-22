import { init, status } from "domfortify"
import DOMPurify from "dompurify"

// Turbo renders its own <turbo-frame>, <turbo-stream> and
// <turbo-cable-stream-source> elements. DOMPurify strips unknown custom
// elements by default, which would silently break Frames, Streams and
// the layout's live queue-badge subscription on every Turbo Drive visit.
// Only the tag name is scoped to Turbo's "turbo-" namespace here: the
// attribute name still has to be on this explicit list. A wildcard
// attributeNameCheck would also let through attributes DOMPurify
// otherwise always strips, like onclick, on any matching element.
const customElementHandling = {
  tagNameCheck: /^turbo-/,
  // must list ALL attributes, even the ones that DOMPurify allows by default.
  attributeNameCheck: /^(?:id|class|target|targets|action|src|loading|busy|complete|disabled|autoscroll|refresh|channel|signed-stream-name|request-id|method|scroll|data-[\w-]+)$/,
  allowCustomizedBuiltInElements: false
}

init({
  SANITIZER: DOMPurify,
  SANITIZER_CONFIG: {
    CUSTOM_ELEMENT_HANDLING: customElementHandling
  }
})

if (!status().protected) {
  console.warn("DOMFortify is not protecting this page:", status().reason)
}

// Turbo Drive builds every page snapshot with `new DOMParser().parseFromString(html, "text/html")`,
// handing it Turbo's own same-origin fetch response as a bare string.
// The DOMFortify default parser strips the <head> elements. This results in Turbo Drive fallback to
// page reload (since it thought that the `data-turbo-track` element changed).
//
// We route this through a custom policy that allows whole documents.
// Any other sink (like element.innerHTML) still uses the DOMFortify default policy.
if (window.trustedTypes?.createPolicy) {
  const turboDrivePolicy = window.trustedTypes.createPolicy("turbo-drive", {
    createHTML: html => DOMPurify.sanitize(html, {
      WHOLE_DOCUMENT: true,
      ADD_TAGS: [ "title", "meta", "link", "base", "script", "style" ],
      ADD_ATTR: [ "charset", "content", "http-equiv", "property" ],
      CUSTOM_ELEMENT_HANDLING: customElementHandling
    })
  })

  const nativeParseFromString = DOMParser.prototype.parseFromString
  DOMParser.prototype.parseFromString = function (html, type, ...rest) {
    const isDOMParserParseFromStringHTMLSink = typeof html === "string" && type === "text/html"
    const trusted = isDOMParserParseFromStringHTMLSink ? turboDrivePolicy.createHTML(html) : html
    return nativeParseFromString.call(this, trusted, type, ...rest)
  }
}
