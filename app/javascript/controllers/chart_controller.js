import { Controller } from "@hotwired/stimulus"
import uPlot from "uplot"

// The stats page's charts. The server sends every number (see
// RegistrationStats::Series#to_chart) and the same numbers as a table under
// each chart, so this only draws: nothing here counts or rounds.
//
// Two kinds:
//   - "outcomes": one stacked bar per hour or day, split by what became of the
//     signups, with the flagged ones as a line over it.
//   - "shared": signups across the participating herds as bars, with the
//     signal hits as a line.
//
// Colours come from CSS custom properties on the element (see .chart in
// application.css): a canvas cannot use a Tailwind class, and reading them
// keeps light and dark in the stylesheet like everything else.
const OUTCOMES = ["pending", "approved", "approved_elsewhere", "rejected", "rejected_elsewhere", "expired"]
const HEIGHT = 240
const DARK = window.matchMedia("(prefers-color-scheme: dark)")

export default class extends Controller {
  static values = { series: Object, kind: String, labels: Object }

  connect() {
    this.redraw = () => this.draw()
    DARK.addEventListener("change", this.redraw)
    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(this.element)
    this.draw()
  }

  disconnect() {
    DARK.removeEventListener("change", this.redraw)
    this.resizeObserver.disconnect()
    this.destroy()
  }

  // A Turbo morph refresh keeps the element and updates the value when the
  // numbers changed; drawn again either way, since the morph also takes away
  // everything uPlot put inside it, which the server never rendered.
  seriesValueChanged() {
    if (this.plot) this.draw()
  }

  morphed(event) {
    if (event.target === this.element) this.draw()
  }

  draw() {
    this.destroy()
    this.style = getComputedStyle(this.element)
    const { series, data } = this.kindValue === "outcomes" ? this.outcomes() : this.shared()
    const options = {
      width: this.element.clientWidth,
      height: HEIGHT,
      series: [{ label: this.seriesValue.unit === "day" ? "Day (UTC)" : "Hour" }, ...series],
      axes: [this.axis(), this.axis()],
      scales: { x: { time: true }, y: { range: (_u, _min, max) => [0, Math.max(max, 1)] } },
      cursor: { points: { show: false } },
      legend: { live: true }
    }
    // Days are UTC days; drawn in the viewer's zone, each would start at some
    // odd local hour.
    if (this.seriesValue.unit === "day") options.tzDate = ts => uPlot.tzDate(new Date(ts * 1000), "Etc/UTC")

    this.plot = new uPlot(options, data, this.element)
  }

  resize() {
    if (this.plot && this.plot.width !== this.element.clientWidth) {
      this.plot.setSize({ width: this.element.clientWidth, height: HEIGHT })
    }
  }

  destroy() {
    this.plot?.destroy()
    this.plot = null
  }

  // uPlot has no stacking of its own: each bar is drawn as the running total up
  // to its outcome, tallest first so the shorter ones paint over it, and the
  // legend shows the outcome's own count rather than the running total.
  outcomes() {
    const raw = this.seriesValue
    const labels = this.labelsValue
    let running = raw.t.map(() => 0)
    const stacked = OUTCOMES.map(outcome => (running = running.map((sum, i) => sum + raw[outcome][i])))

    const bars = OUTCOMES.map((outcome, k) => ({ outcome, data: stacked[k] })).reverse()
    return {
      series: [
        ...bars.map(({ outcome }) => this.bar(labels[outcome], this.color(outcome), (_u, _v, _s, i) => raw[outcome][i])),
        this.line("Flagged", this.color("flagged"), { dash: [4, 3] })
      ],
      data: [raw.t, ...bars.map(b => b.data), raw.flagged]
    }
  }

  shared() {
    const raw = this.seriesValue
    return {
      series: [this.bar("Signups", this.color("signups")), this.line("Signal hits", this.color("signalled"))],
      data: [raw.t, raw.signups, raw.signalled]
    }
  }

  bar(label, color, value) {
    const series = {
      label,
      fill: color,
      stroke: color,
      width: 0,
      paths: uPlot.paths.bars({ size: [0.85, 48], align: 0 }),
      points: { show: false }
    }
    if (value) series.value = (u, v, s, i) => (i == null ? "--" : value(u, v, s, i))
    return series
  }

  line(label, color, options = {}) {
    return { label, stroke: color, width: 1.5, points: { show: false }, ...options }
  }

  axis() {
    return {
      stroke: this.color("axis"),
      grid: { stroke: this.color("grid"), width: 1 },
      ticks: { stroke: this.color("grid"), width: 1 }
    }
  }

  color(name) {
    return this.style.getPropertyValue(`--chart-${name}`).trim()
  }
}
