import { Controller } from "@hotwired/stimulus"

// What each reason turned out to be, kept for the life of the page so a Turbo
// snapshot restored by Back shows the translation it was cached with instead
// of flashing it and starting over. Keyed by the text itself: a reason is a
// few hundred bytes, and a moderator reads at most a few hundred per visit.
const known = new Map()

// Names and translates a reason for joining written in a language the
// moderator may not read, with the browser's built-in, on-device models
// (Chrome's LanguageDetector and Translator APIs). The reason never leaves the
// browser, so this needs no processor in the privacy notice and no setup.
// Browsers without the APIs keep the button hidden; their own page translation
// still works on the original.
export default class extends Controller {
  static targets = ["source", "language", "button", "status", "output"]

  // Short reasons are where detection is weakest; below this we rather say
  // nothing than label a reason with the wrong language.
  static minConfidence = 0.5

  // A browser can expose the APIs with nothing behind them (in Electron,
  // availability() can hang). Past this, offer the button and let the click
  // find out.
  static availabilityTimeout = 1000

  connect() {
    if (!("LanguageDetector" in window && "Translator" in window)) return

    // The page language, not the browser one: see relative_time_controller.
    this.targetLanguage = (document.documentElement.lang || "en").split("-")[0]
    this.names = new Intl.DisplayNames([this.targetLanguage], { type: "language" })

    const key = this.#text()
    if (!known.has(key)) known.set(key, {})
    this.state = known.get(key)
    this.state.busy = false
    this.reconcile()

    if (!this.state.detected) this.#detectIfReady()
  }

  async translate() {
    this.state.busy = true
    this.reconcile()
    try {
      // Detection is deferred to here when its model still had to be
      // downloaded: create() may only start a download on a user gesture.
      if (!this.state.detected) await this.#detect()
      const source = this.state.source
      if (!source) return this.#finish("Your browser could not tell which language this is.")
      if (source === this.targetLanguage) return this.#finish(`This is already in ${this.#name(source)}.`)

      const pair = { sourceLanguage: source, targetLanguage: this.targetLanguage }
      const availability = await Translator.availability(pair)
      if (availability === "unavailable") {
        return this.#finish(`Your browser cannot translate ${this.#name(source)} to ${this.#name(this.targetLanguage)}.`)
      }
      // A click allows a download for a few seconds only, and downloading the
      // detector may have used them up. Ask for a fresh click rather than let
      // create() fail with NotAllowedError.
      if (availability !== "available" && navigator.userActivation && !navigator.userActivation.isActive) {
        return this.#finish(`This is ${this.#name(source)}. Click again to download its translation model.`)
      }

      const translator = await Translator.create({ ...pair, monitor: this.#monitor() })
      this.state.translation = await translator.translate(this.#text())
      translator.destroy()
      this.#finish(`Translated from ${this.#name(source)} by your browser, on this device.`)
    } catch (error) {
      console.error(error)
      this.#finish("Your browser could not translate this. Try again, or use its own page translation.")
    }
  }

  // Also runs on every turbo:render (see the markup): a morph refresh patches
  // the lang, the button and the translation back to the server-rendered
  // markup without disconnecting the controller.
  reconcile() {
    if (!this.state) return

    const { source, detected, translation, busy, status } = this.state
    if (source) {
      this.sourceTarget.lang = source
      this.languageTarget.textContent = this.#name(source)
    }
    this.languageTarget.hidden = !source

    // Only offer what can help: not before we know whether detection can
    // run, not for a language nobody could tell, not when it is already in
    // the page language, and not once it has been translated.
    const translatable = detected ? source && source !== this.targetLanguage : this.state.offer
    this.buttonTarget.hidden = !translatable || !!translation
    this.buttonTarget.disabled = !!busy
    this.buttonTarget.textContent = `Translate to ${this.#name(this.targetLanguage)}`

    // data-turbo-permanent keeps morphs from emptying this live region, and
    // the guard keeps unchanged text from being announced again.
    if (this.statusTarget.textContent !== (status || "")) this.statusTarget.textContent = status || ""

    this.outputTarget.textContent = translation || ""
    this.outputTarget.lang = this.targetLanguage
    this.outputTarget.hidden = !translation
  }

  async #detectIfReady() {
    try {
      // "downloadable" models need a user gesture to fetch, so leave detection
      // to the click instead of naming nothing on load.
      if (await this.#withTimeout(LanguageDetector.availability()) === "available") await this.#detect()
    } catch {
      // Rejected or never settled: the click tries again.
    }
    this.state.offer = true
    this.reconcile()
  }

  async #detect() {
    const detector = await LanguageDetector.create({ monitor: this.#monitor() })
    const [best] = await detector.detect(this.#text())
    detector.destroy()
    // Recorded either way, so an undetermined reason is neither offered nor
    // detected again on every click with the same result.
    this.state.detected = true
    if (best && best.detectedLanguage !== "und" && best.confidence >= this.constructor.minConfidence) {
      // The full tag: zh-Hant passed on as zh would be read as Simplified.
      this.state.source = best.detectedLanguage
    }
  }

  #withTimeout(promise) {
    return Promise.race([
      promise,
      new Promise((_, reject) => setTimeout(() => reject(new Error("timed out")), this.constructor.availabilityTimeout))
    ])
  }

  #monitor() {
    return (monitor) => monitor.addEventListener("downloadprogress", (event) => {
      this.state.status = `Downloading a language model… ${Math.round(event.loaded * 100)}%`
      this.reconcile()
    })
  }

  #finish(status) {
    this.state.busy = false
    this.state.status = status
    this.reconcile()
  }

  // textContent, so watchword highlighting does not end up in the input.
  #text() {
    return this.sourceTarget.textContent.trim()
  }

  // Intl.DisplayNames throws on a malformed tag.
  #name(code) {
    try {
      return this.names.of(code) || code
    } catch {
      return code
    }
  }
}
