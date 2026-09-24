import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Bulk claim / release / approve / reject on the queue page, for when a wave of
// probe signups arrives and every one of them is plainly a reject.
//
// The server cannot do this in one request -- fifty inline Mastodon pushes
// outlive any sane request timeout -- so this sends ONE request per row, to the
// same endpoints the detail page uses (asking for JSON), strictly one at a
// time, and collects the answers in a <dialog>.
//
// Mastodon's admin API is rate limited per token. Each decision response
// carries the remaining budget, and the loop:
//   - pauses until the window resets once the budget drops to RESERVE, leaving
//     headroom for the 403 follow-up read and the moderator's other tabs;
//   - pauses for retry_after when Mastodon answered 429 anyway. That item is
//     NOT re-sent: the server already queued it for a background retry.
// A dead token or an unexpected (non-JSON) answer stops the run outright, as
// does Mastodon being unreachable for MAX_TRANSPORT_FAILURES in a row.
const RESERVE = 10
const MAX_TRANSPORT_FAILURES = 3

// Spelled out in full so Tailwind finds them in this file.
const TONES = {
  ok: "bg-emerald-100 dark:bg-emerald-900 text-emerald-900 dark:text-emerald-200",
  warn: "bg-amber-100 dark:bg-amber-900 text-amber-900 dark:text-amber-200",
  error: "bg-red-100 dark:bg-red-900 text-red-900 dark:text-red-200",
  busy: "bg-sky-100 dark:bg-sky-900 text-sky-900 dark:text-sky-200",
  muted: "bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-300"
}

// Outcomes after which the row has left the pending list, so keeping it
// selected would only select something no longer on screen.
const SETTLED = new Set(["succeeded", "queued", "conflict", "already_resolved"])

class FatalError extends Error {}

export default class extends Controller {
  static targets = ["checkbox", "all", "count", "button", "dialog", "title", "progress", "results", "stop", "close"]

  initialize() {
    this.selected = new Set()
    this.running = false
  }

  // Also fires for a row swapped in by a turbo stream (the "c" claim toggle
  // replaces the whole <li>), which would otherwise come back unticked.
  checkboxTargetConnected(checkbox) {
    checkbox.checked = this.selected.has(checkbox.value)
    this.sync()
  }

  checkboxTargetDisconnected() {
    this.sync()
  }

  toggle(event) {
    const checkbox = event.target
    checkbox.checked ? this.selected.add(checkbox.value) : this.selected.delete(checkbox.value)
    this.sync()
  }

  toggleAll(event) {
    for (const checkbox of this.checkboxTargets) {
      checkbox.checked = event.target.checked
      checkbox.checked ? this.selected.add(checkbox.value) : this.selected.delete(checkbox.value)
    }
    this.sync()
  }

  // Filtering or paging replaced the frame: a fresh page, a fresh selection.
  reset() {
    this.selected.clear()
    this.sync()
  }

  // Every claim and decision broadcasts a refresh, and the morph resets each
  // checkbox to the server's (unticked) markup. Put the ticks back, and forget
  // rows that have left the list.
  restore() {
    const checkboxes = this.checkboxTargets
    const present = new Set(checkboxes.map(checkbox => checkbox.value))
    for (const id of this.selected) if (!present.has(id)) this.selected.delete(id)
    for (const checkbox of checkboxes) checkbox.checked = this.selected.has(checkbox.value)
    this.sync()
  }

  sync() {
    const checkboxes = this.checkboxTargets
    const total = checkboxes.length
    const count = checkboxes.filter(checkbox => this.selected.has(checkbox.value)).length

    if (this.hasAllTarget) {
      this.allTarget.checked = count > 0 && count === total
      this.allTarget.indeterminate = count > 0 && count < total
    }
    if (this.hasCountTarget) this.countTarget.textContent = count > 0 ? `${count} selected` : "Select all"
    for (const button of this.buttonTargets) button.disabled = count === 0 || this.running
  }

  get selectedItems() {
    return this.checkboxTargets
      .filter(checkbox => this.selected.has(checkbox.value))
      .map(checkbox => ({
        id: checkbox.value,
        username: checkbox.dataset.username,
        decisionUrl: checkbox.dataset.decisionUrl,
        claimUrl: checkbox.dataset.claimUrl,
        claimedBy: checkbox.dataset.claimedBy,
        claimerName: checkbox.dataset.claimerName
      }))
  }

  // --- actions ---------------------------------------------------------------

  // Claiming is reversible and never reaches Mastodon: no confirmation, no
  // pacing, and the selection is kept so a decision can follow.
  claim() {
    this.run({
      title: "Claim", items: this.selectedItems, keepSelection: true,
      perform: async (item) => {
        if (item.claimedBy === "me") return { label: "Already yours", tone: "muted" }

        const json = await this.send(item.claimUrl, "POST")
        if (json.outcome !== "claimed") return { label: "Taken", tone: "warn", message: json.message }

        this.markClaimed(item, "me")
        return { label: "Claimed", tone: "ok" }
      }
    })
  }

  // The endpoint would release anyone's claim; a bulk release never should.
  release() {
    this.run({
      title: "Release", items: this.selectedItems, keepSelection: true,
      perform: async (item) => {
        if (item.claimedBy === "other") return { label: "Skipped", tone: "muted", message: `Claimed by ${item.claimerName || "someone else"}` }
        if (item.claimedBy !== "me") return { label: "Not claimed", tone: "muted" }

        await this.send(item.claimUrl, "DELETE")
        this.markClaimed(item, "none")
        return { label: "Released", tone: "ok" }
      }
    })
  }

  // The refresh broadcast that re-renders the row arrives debounced, seconds
  // later; a Release straight after a Claim must not act on the old state.
  markClaimed(item, claimedBy) {
    const checkbox = this.checkboxTargets.find(checkbox => checkbox.value === item.id)
    if (checkbox) checkbox.dataset.claimedBy = claimedBy
  }

  approve() { this.decide("approve") }

  reject() { this.decide("reject") }

  async decide(action) {
    const items = this.selectedItems
    if (items.length === 0 || this.running) return

    const verb = action === "approve" ? "Approve" : "Reject"
    const noun = items.length === 1 ? "request" : "requests"
    const others = items.filter(item => item.claimedBy === "other").length
    let message = `${verb} ${items.length} ${noun}?`
    if (action === "reject") message += " Mastodon deletes the accounts on rejection, and this cannot be undone."
    if (others > 0) message += ` ${others} of them ${others === 1 ? "is" : "are"} claimed by another moderator.`

    if (!await Turbo.config.forms.confirm(message)) return

    this.run({
      title: verb, items,
      perform: async (item) => this.decisionResult(action, await this.send(item.decisionUrl, "POST", { decision_action: action }))
    })
  }

  decisionResult(action, json) {
    const result = { outcome: json.outcome, message: json.message }
    const { remaining, reset_at: resetAt } = json.rate_limit || {}
    if (remaining != null && remaining <= RESERVE && resetAt) result.pauseUntil = Date.parse(resetAt)

    switch (json.outcome) {
      case "succeeded":
        return { ...result, label: action === "approve" ? "Approved" : "Rejected", tone: "ok", message: undefined }
      case "queued":
        if (json.retry_after != null) {
          return { ...result, label: "Queued", tone: "warn", message: "Rate limited by Mastodon, retrying in the background.",
            pauseUntil: Math.max(result.pauseUntil || 0, Date.now() + json.retry_after * 1000) }
        }
        return { ...result, label: "Queued", tone: "warn", transportFailure: true }
      case "conflict":
        return { ...result, label: "Conflict", tone: "warn" }
      case "already_resolved":
        return { ...result, label: "Already decided", tone: "muted" }
      case "unauthorized":
        return { ...result, label: "Failed", tone: "error", fatal: true }
      default:
        return { ...result, label: "Failed", tone: "error" }
    }
  }

  // Plain fetch, not Turbo.fetch: Turbo.fetch tags the request so the refresh
  // it broadcasts skips this very tab, and here that refresh is exactly what
  // takes decided rows off the list behind the dialog.
  async send(url, method, params) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    let response
    try {
      response = await fetch(url, {
        method,
        body: params ? new URLSearchParams(params) : undefined,
        headers: { "Accept": "application/json", ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}) }
      })
    } catch (error) {
      throw new FatalError(`Waterhole could not be reached (${error.message}).`)
    }

    // A signed-out request is redirected to the HTML sign-in page.
    if (!(response.headers.get("Content-Type") || "").includes("application/json")) {
      throw new FatalError(`Unexpected answer from Waterhole (HTTP ${response.status}). Reload the page; you may need to sign in again.`)
    }
    return response.json()
  }

  // --- the run -----------------------------------------------------------------

  async run({ title, items, perform, keepSelection = false }) {
    if (items.length === 0 || this.running) return

    this.running = true
    this.stopped = false
    this.sync()

    const rows = this.openDialog(title, items)
    const tally = new Map()
    let transportFailures = 0
    let stopReason = null

    for (const [index, item] of items.entries()) {
      if (this.stopped) {
        for (const rest of items.slice(index)) this.render(rows.get(rest.id), { label: "Not attempted", tone: "muted" })
        tally.set("Not attempted", (tally.get("Not attempted") || 0) + items.length - index)
        break
      }

      this.progressTarget.textContent = `${index + 1} of ${items.length}: @${item.username}`
      this.render(rows.get(item.id), { label: "Working…", tone: "busy" })

      let result
      try {
        result = await perform(item)
      } catch (error) {
        result = { label: "Failed", tone: "error", message: error.message, fatal: error instanceof FatalError }
      }

      this.render(rows.get(item.id), result)
      tally.set(result.label, (tally.get(result.label) || 0) + 1)
      if (!keepSelection && SETTLED.has(result.outcome)) this.selected.delete(item.id)

      transportFailures = result.transportFailure ? transportFailures + 1 : 0
      if (transportFailures >= MAX_TRANSPORT_FAILURES) {
        this.stopped = true
        stopReason = "Stopped: Mastodon is not responding."
      }
      if (result.fatal) {
        this.stopped = true
        stopReason = `Stopped: ${result.message}`
      }

      if (result.pauseUntil && index < items.length - 1 && !this.stopped) await this.pause(result.pauseUntil)
    }

    const summary = [...tally].map(([label, count]) => `${count} ${label.toLowerCase()}`).join(", ")
    this.progressTarget.textContent = stopReason ? `${stopReason} ${summary}.` : `Done: ${summary}.`
    this.stopTarget.hidden = true
    this.closeTarget.disabled = false
    this.closeTarget.focus()

    this.running = false
    this.restore()
  }

  async pause(until) {
    while (!this.stopped && Date.now() < until) {
      const seconds = Math.ceil((until - Date.now()) / 1000)
      this.progressTarget.textContent = `Paused for Mastodon's rate limit, resuming in ${seconds}s.`
      await new Promise(resolve => {
        this.wake = resolve
        setTimeout(resolve, Math.min(1000, until - Date.now()))
      })
    }
    this.wake = null
  }

  stop() {
    this.stopped = true
    this.stopTarget.disabled = true
    this.progressTarget.textContent = "Stopping after the current request…"
    this.wake?.()
  }

  // --- the dialog --------------------------------------------------------------

  openDialog(title, items) {
    this.titleTarget.textContent = `${title}: ${items.length} ${items.length === 1 ? "request" : "requests"}`
    this.progressTarget.textContent = ""
    this.resultsTarget.replaceChildren()
    this.stopTarget.hidden = false
    this.stopTarget.disabled = false
    this.closeTarget.disabled = true

    const rows = new Map()
    for (const item of items) {
      const row = document.createElement("li")
      row.className = "flex flex-wrap items-baseline gap-x-3 gap-y-1 py-2"

      const name = document.createElement("span")
      name.className = "font-medium"
      name.textContent = `@${item.username}`

      const badge = document.createElement("span")
      const message = document.createElement("span")
      message.className = "basis-full text-xs text-stone-500 dark:text-stone-400"
      message.hidden = true

      row.append(name, badge, message)
      this.resultsTarget.append(row)
      rows.set(item.id, row)
      this.render(row, { label: "Waiting", tone: "muted" })
    }

    this.dialogTarget.showModal()
    return rows
  }

  render(row, { label, tone, message }) {
    const [, badge, detail] = row.children
    badge.className = `ml-auto rounded-full px-2 py-0.5 text-xs font-medium ${TONES[tone]}`
    badge.textContent = label
    detail.textContent = message || ""
    detail.hidden = !message
    if (tone === "busy") row.scrollIntoView({ block: "nearest" })
  }

  // Escape mid-run means "stop", not "hide the only view of what's happening".
  cancel(event) {
    if (!this.running) return
    event.preventDefault()
    this.stop()
  }

  closeOnBackdrop(event) {
    if (!this.running && event.target === this.dialogTarget) this.dialogTarget.close()
  }
}
