import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const WORKER_URL = "/service-worker.js"

// Trusted Types makes register() a sink, and the default policy refuses every
// script URL. This one allows exactly the one worker, and only exists once a
// moderator has asked for it. See config/initializers/content_security_policy.rb.
let workerPolicy
function workerScriptURL() {
  if (!window.trustedTypes?.createPolicy) return WORKER_URL

  workerPolicy ??= window.trustedTypes.createPolicy("push-service-worker", {
    createScriptURL: url => {
      if (url === WORKER_URL) return url
      throw new TypeError(`Refusing service worker ${url}`)
    }
  })
  return workerPolicy.createScriptURL(WORKER_URL)
}

function decodeKey(base64url) {
  const base64 = base64url.replaceAll("-", "+").replaceAll("_", "/")
  return Uint8Array.from(atob(base64), character => character.charCodeAt(0))
}

function onAppleMobile() {
  return /iPhone|iPad|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
}

// Turns push on and off for this browser. Asks for permission only on a click,
// and registers the worker only then too, so visiting the settings page changes
// nothing. A subscription found in the browser may belong to whoever else shares
// it, so it counts as enabled only if the server says it is this moderator's.
export default class extends Controller {
  static targets = [ "status", "enable", "disable", "test", "timeZone", "zoneName" ]
  static values = { publicKey: String, subscriptionsUrl: String, checkUrl: String, testUrl: String, currentUrl: String, savedZone: String }

  connect() {
    this.sync()
  }

  // Also runs on every turbo:render (see the markup): saving the form morphs this
  // page back to how the server rendered it, which knows nothing of this browser.
  sync() {
    this.useBrowserTimeZone()
    this.refresh()
  }

  async refresh() {
    if (!this.supported) {
      this.show(onAppleMobile() && !navigator.standalone
        ? "On iPhone and iPad, add Waterhole to your home screen and open it from there first."
        : "This browser doesn't support push notifications.")
      return
    }

    if (Notification.permission === "denied") {
      this.show("Notifications are blocked for this site. Allow them in your browser's settings, then reload.")
      return
    }

    try {
      const subscription = await this.currentSubscription()
      if (subscription && (await this.check(subscription)).enabled) {
        this.show("Notifications are on in this browser.", this.testTarget, this.disableTarget)
      } else {
        this.show("Notifications are off in this browser.", this.enableTarget)
      }
    } catch (error) {
      this.showUnreachable(error)
    }
  }

  enable() {
    return this.whileBusy(async () => {
      try {
        if (await Notification.requestPermission() !== "granted") return this.refresh()

        await navigator.serviceWorker.register(workerScriptURL(), { scope: "/" })
        const registration = await navigator.serviceWorker.ready
        await this.dropAbandonedSubscription(registration)
        const { endpoint, keys } = (await this.subscribe(registration)).toJSON()

        const response = await this.send("POST", this.subscriptionsUrlValue, {
          push_subscription: { endpoint, p256dh: keys.p256dh, auth: keys.auth },
          time_zone: this.browserTimeZone
        })
        if (!response.ok) throw new Error(`Saving the subscription: ${response.status}`)

        await this.refresh()
      } catch (error) {
        console.error(error)
        this.show("Turning notifications on failed. Please try again.", this.enableTarget)
      }
    })
  }

  disable() {
    return this.whileBusy(async () => {
      try {
        const subscription = await this.currentSubscription()
        if (subscription) {
          const response = await this.send("DELETE", this.currentUrlValue, { push_subscription: { endpoint: subscription.endpoint } })
          if (!response.ok) throw new Error(`Turning off: ${response.status}`)

          // Someone else who shares this browser may still be using the subscription.
          if (!(await response.json()).in_use) await subscription.unsubscribe()
        }
        // A refresh: morphs the list of browsers, and turbo:render updates the rest.
        Turbo.visit(window.location.href, { action: "replace" })
      } catch (error) {
        this.showUnreachable(error)
      }
    })
  }

  sendTest() {
    return this.whileBusy(async () => {
      try {
        const subscription = await this.currentSubscription()
        if (!subscription) return this.refresh()

        const { status, ok } = await this.send("POST", this.testUrlValue, { push_subscription: { endpoint: subscription.endpoint } })
        if (ok) {
          this.statusTarget.textContent = "Test notification sent. It should arrive within a moment."
        } else if (status === 429) {
          this.statusTarget.textContent = "That's a lot of tests. Please wait a minute."
        } else if (status === 410 || status === 404) {
          // Gone means the push service won't take it from anyone, so the next
          // subscribe() has to get a new one rather than this one back.
          if (status === 410) await subscription.unsubscribe()
          this.show("This browser's subscription has ended. Please turn notifications on again.", this.enableTarget)
        } else {
          this.statusTarget.textContent = "The push service didn't accept the test. Please try again later."
        }
      } catch (error) {
        this.showUnreachable(error)
      }
    })
  }

  // ---

  get supported() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
  }

  get browserTimeZone() {
    return Intl.DateTimeFormat().resolvedOptions().timeZone
  }

  // Saving from this browser moves the moderator to its zone, for all their
  // browsers, so what the page says has to be what will happen.
  useBrowserTimeZone() {
    const browser = this.browserTimeZone
    if (!browser) return

    if (this.hasTimeZoneTarget) this.timeZoneTarget.value = browser
    if (this.hasZoneNameTarget) {
      const saved = this.savedZoneValue
      this.zoneNameTarget.textContent = !saved || saved === browser ? browser : `${saved}, or ${browser} once you save`
    }
  }

  async currentSubscription() {
    const registration = await navigator.serviceWorker.getRegistration("/")
    return registration?.pushManager.getSubscription()
  }

  async check(subscription) {
    const response = await this.send("POST", this.checkUrlValue, { push_subscription: { endpoint: subscription.endpoint } })
    if (!response.ok) throw new Error(`Checking this browser: ${response.status}`)
    return response.json()
  }

  // A subscription the server has no record of was most likely removed because it
  // stopped working, and subscribe() would only hand back the same one.
  async dropAbandonedSubscription(registration) {
    const existing = await registration.pushManager.getSubscription()
    if (existing && !(await this.check(existing)).in_use) await existing.unsubscribe()
  }

  async subscribe(registration) {
    const options = { userVisibleOnly: true, applicationServerKey: decodeKey(this.publicKeyValue) }
    try {
      return await registration.pushManager.subscribe(options)
    } catch (error) {
      // The operator changed the key pair: the old subscription has to go first.
      if (error.name !== "InvalidStateError") throw error

      await (await registration.pushManager.getSubscription())?.unsubscribe()
      return registration.pushManager.subscribe(options)
    }
  }

  // A signed-out request is redirected to the HTML sign-in page, which would look
  // like success. Refusing the redirect makes it fail like any other lost request.
  send(method, url, body) {
    return fetch(url, {
      method,
      redirect: "error",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: JSON.stringify(body)
    })
  }

  async whileBusy(action) {
    const buttons = [ this.enableTarget, this.testTarget, this.disableTarget ]
    buttons.forEach(button => button.disabled = true)
    try {
      await action()
    } finally {
      buttons.forEach(button => button.disabled = false)
    }
  }

  showUnreachable(error) {
    console.error(error)
    this.show("Waterhole could not be reached. Reload the page; you may need to sign in again.")
  }

  show(message, ...buttons) {
    this.statusTarget.textContent = message
    for (const button of [ this.enableTarget, this.testTarget, this.disableTarget ]) {
      button.hidden = !buttons.includes(button)
    }
  }
}
