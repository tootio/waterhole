import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  close(event) {
    event.currentTarget.closest("[role=status]")?.remove()
  }
}
